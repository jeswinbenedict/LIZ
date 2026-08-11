/// Generic cursor-paginated result used by every feed. The [cursor] is opaque;
/// callers pass it straight back to fetch the next page. `null` means no more.
class Paginated<T> {
  const Paginated({required this.items, this.cursor});

  final List<T> items;
  final String? cursor;

  bool get hasMore => cursor != null;

  Paginated<T> append(Paginated<T> next) =>
      Paginated(items: [...items, ...next.items], cursor: next.cursor);

  static Paginated<T> empty<T>() => Paginated<T>(items: const [], cursor: null);
}
