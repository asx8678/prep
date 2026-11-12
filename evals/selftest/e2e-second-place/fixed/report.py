def reorder_lines(items, limit):
    """One line for each item with at most `limit` pieces left."""
    return [f"{name}: reorder" for name, count in items if count <= limit]
