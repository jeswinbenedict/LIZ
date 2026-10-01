import 'json.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
  });

  final String id;
  final String name;
  final String slug;
  final String? icon;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: asString(j['id']),
    name: asString(j['name']),
    slug: asString(j['slug']),
    icon: asStringOrNull(j['icon']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'icon': icon,
  };
}
