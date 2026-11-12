"""Prints a greeting. Run: python3 cli.py [--name NAME] [--shout] [--times N]"""
import sys

OPTIONS = {
    "--name": "who to greet (default: world)",
    "--shout": "print the greeting in capital letters",
    "--times": "how often to print the greeting (default: 1)",
}


def greeting(name="world", shout=False):
    text = f"hello, {name}"
    return text.upper() if shout else text


def main(argv):
    name, shout, times = "world", False, 1
    args = list(argv)
    while args:
        option = args.pop(0)
        if option not in OPTIONS:
            raise SystemExit(f"unknown option: {option}")
        if option == "--name":
            name = args.pop(0)
        elif option == "--shout":
            shout = True
        elif option == "--times":
            times = int(args.pop(0))
    for _ in range(times):
        print(greeting(name, shout))


if __name__ == "__main__":
    main(sys.argv[1:])
