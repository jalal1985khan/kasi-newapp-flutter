class Article {
  final String title;
  final String? description;
  final String? urlToImage;
  final String url;
  final String? sourceName;
  final String? publishedAt;
  final String? category;
  final String? content;

  Article({
    required this.title,
    this.description,
    this.urlToImage,
    required this.url,
    this.sourceName,
    this.publishedAt,
    this.category,
    this.content,
  });

  factory Article.fromJson(Map<String, dynamic> json, {String? category}) {
    return Article(
      title: json['title'] ?? '',
      description: json['description'],
      urlToImage: json['urlToImage'],
      url: json['url'] ?? '',
      sourceName: json['source']?['name'],
      publishedAt: json['publishedAt'],
      category: category,
      content: json['content'],
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'urlToImage': urlToImage,
    'url': url,
    'source': {'name': sourceName},
    'publishedAt': publishedAt,
    'category': category,
    'content': content,
  };
}
