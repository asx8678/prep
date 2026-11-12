def total(lines):
    """Cents for all lines; a line is a price and a quantity."""
    return sum(round(float(price) * 100) * quantity for price, quantity in lines)
