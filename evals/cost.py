"""Print where a Claude Code session's cost went: by message from the person,
and by kind (advisor, the model's own output, first read, re-reading).

Usage: python3 -I evals/cost.py <session.jsonl>...
A project's sessions are in ~/.claude/projects/<project folder>/.

The session records are not documented; this was written against Claude Code
2.1.322. PRICES was fitted to the cost those records hold, so every run
checks it: each priced model's recorded cost is recomputed from its recorded
tokens, and a difference is marked MISMATCH. A session that used a model
without a price gets one line: the cost recorded for each model.
"""
import json
import sys
from pathlib import Path

# $ per million tokens: input, output, cache read, 1-hour cache write, 5-minute cache write
PRICES = {"claude-fable-5-2": (8.0, 40.0, 0.20, 16.0, 10.0)}
KINDS = ("advisor", "model output", "first read", "re-reading")
NOT_THE_PERSON = ("<local-command", "<system-reminder", "<task-notification", "<bash-", "Base directory for this skill")


def dollars(model, *tokens):
    return sum(count * price for count, price in zip(tokens, PRICES[model])) / 1e6


def tokens_of(call):
    written = call.get("cache_creation") or {}
    return (call.get("input_tokens", 0), call.get("output_tokens", 0), call.get("cache_read_input_tokens", 0),
            written.get("ephemeral_1h_input_tokens", 0), written.get("ephemeral_5m_input_tokens", 0))


def said(content):
    """The start of a message the person typed, or "" for anything else."""
    if isinstance(content, list):
        if any(block.get("type") == "tool_result" for block in content):
            return ""
        content = next((block["text"] for block in content if block.get("type") == "text"), "")
    text = content.strip()
    if text.startswith(NOT_THE_PERSON):
        return ""
    if "<command-name>" in text:
        text = text.split("<command-name>")[1].split("</command-name>")[0] + " " + text.partition("<command-args>")[2].split("</command-args>")[0]
    return " ".join(text.split())[:60]


def report(path):
    usage, order, recorded = {}, [], None
    for line in path.open(errors="replace"):
        record = json.loads(line)
        kind, message = record.get("type"), record.get("message") or {}
        if kind == "cost-state":
            recorded = record
        elif kind == "system" and record.get("subtype") == "turn_duration":
            order.append(("minutes", record["durationMs"] / 60000))
        elif kind == "assistant" and message.get("usage"):
            # One message is written as several records, each with the same usage.
            if message["id"] not in usage:
                order.append(("message", message["id"]))
                usage[message["id"]] = (message["model"], message["usage"])
        elif kind == "user" and not record.get("isMeta") and said(message.get("content")):
            order.append(("person", said(message["content"])))

    models = {model for model, _ in usage.values()}
    models |= {call["model"] for _, used in usage.values() for call in used["iterations"] if call["type"] == "advisor_message"}
    if not usage:
        print(f"{path.name}: no model calls")
        return
    if models - PRICES.keys():
        line = f"{path.name}: no price for " + ", ".join(sorted(models - PRICES.keys()))
        if recorded:
            minutes = sum(value for what, value in order if what == "minutes")
            line += f"; recorded ${recorded['totalCostUSD']:.2f} in {minutes:.1f} minutes: "
            line += ", ".join(f"{model} ${used['costUSD']:.2f}" for model, used in sorted(recorded["modelUsage"].items()))
        print(line)
        return

    def part(label):
        return dict({kind: 0.0 for kind in KINDS}, label=label, calls=0, advisor_calls=0, minutes=0.0, thinking=0.0, first=0, last=0)

    parts = [part("(before the first message)")]
    for what, value in order:
        if what == "person":
            parts.append(part(value))
        elif what == "minutes":
            parts[-1]["minutes"] += value
        else:
            now, (model, used) = parts[-1], usage[value]
            now["thinking"] += dollars(model, 0, used["output_tokens_details"]["thinking_tokens"])
            for call in used["iterations"]:
                inp, out, read, write_1h, write_5m = tokens_of(call)
                if call["type"] == "advisor_message":
                    now["advisor_calls"] += 1
                    now["advisor"] += dollars(call["model"], inp, out, read, write_1h, write_5m)
                    continue
                now["calls"] += 1
                now["last"] = inp + read + write_1h + write_5m
                now["first"] = now["first"] or now["last"]
                now["model output"] += dollars(model, 0, out)
                now["first read"] += dollars(model, inp, 0, 0, write_1h, write_5m)
                now["re-reading"] += dollars(model, 0, 0, read)
    parts = [p for p in parts if p["calls"]]
    total = sum(p[kind] for p in parts for kind in KINDS)

    if recorded is None:
        print(f"{path.name}: no recorded cost yet, in this file ${total:.2f}")
    else:
        print(f"{path.name}: recorded ${recorded['totalCostUSD']:.2f}, in this file ${total:.2f}")
        for model, used in recorded["modelUsage"].items():
            if model in PRICES:
                write_1h = used.get("cacheCreationEphemeral1hInputTokens", 0)
                again = dollars(model, used.get("inputTokens", 0), used.get("outputTokens", 0), used.get("cacheReadInputTokens", 0),
                                write_1h, used.get("cacheCreationInputTokens", 0) - write_1h)
                print(f"  price check, {model}: recorded ${used['costUSD']:.2f}, recomputed ${again:.2f}"
                      + ("" if abs(again - used["costUSD"]) < 0.005 else "  MISMATCH"))
    print("     cost  calls  advisor  minutes  context from         to  message from the person")
    for p in parts:
        print(f"  {sum(p[kind] for kind in KINDS):7.2f}  {p['calls']:5d}  {p['advisor_calls']:7d}  {p['minutes']:7.1f}  {p['first']:12d}  {p['last']:9d}  {p['label']}")
    for kind in KINDS:
        spent = sum(p[kind] for p in parts)
        print(f"  {kind:12}  {spent:7.2f}  {100 * spent / total:3.0f}%")
    print(f"  thinking is {sum(p['thinking'] for p in parts):.2f} of the model output")


for name in sys.argv[1:]:
    report(Path(name))
