/// One page of a server-paged list: the items, the cursor for the next page
/// (`null` on the last) and the total when the server knows it.
class Paged<T> {
  const Paged({required this.items, this.nextCursor, this.total});

  final List<T> items;
  final String? nextCursor;
  final int? total;

  bool get hasMore => nextCursor != null;

  Paged<T> append(Paged<T> next) =>
      Paged(items: [...items, ...next.items], nextCursor: next.nextCursor, total: next.total ?? total);
}
