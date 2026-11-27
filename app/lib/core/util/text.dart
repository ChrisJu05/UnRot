/// "1 section", "3 sections".
String plural(int n, String word, [String? pluralWord]) => '$n ${n == 1 ? word : (pluralWord ?? '${word}s')}';
