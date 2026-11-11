import 'dart:ui' show Size;

/// Whether the screen is wide enough for a side-by-side layout: a tablet,
/// a desktop window, or a phone turned on its side.
///
/// 840 is where Material calls a window "expanded". A phone on its side is
/// narrower than that but so short that anything stacked from the bottom
/// leaves no room for the page, so it counts as wide too.
bool isWideLayout(Size size) {
  if (size.width >= 840) return true;
  return size.width > size.height && size.height < 500 && size.width >= 560;
}
