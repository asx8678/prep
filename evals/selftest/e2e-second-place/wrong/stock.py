def low_stock(items, limit):
    """Names of the items with at most `limit` pieces left."""
    return [name for name, count in items if count <= limit]
