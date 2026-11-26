/// Languages offered for generated reels. `source` = same language as the material.
const List<String> reelLanguages = [
  'English',
  'Deutsch',
  'Español',
  'Français',
  'Italiano',
  'Português',
  'Nederlands',
  'Polski',
  'Türkçe',
  'Українська',
  '中文',
  '日本語',
];

/// Human readable label for a language setting value.
String languageLabel(String value) => switch (value) {
  'source' => 'Same as the source',
  'default' => 'App default',
  _ => value,
};
