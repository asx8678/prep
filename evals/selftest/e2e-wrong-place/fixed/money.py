def to_cents(text):
    """Cents for an amount such as "12.50" or "7"."""
    whole, _, part = text.partition(".")
    return int(whole) * 100 + int((part + "00")[:2])
