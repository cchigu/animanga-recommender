import 'dart:math';

import 'package:flutter/material.dart';

/// A recommended title. In Milestone 1 these are hard-coded demo picks;
/// from Milestone 5 on they come from MyAnimeList + AniList.
class PickedTitle {
  final String name;
  final bool isAnime;
  final String format; // TV, Movie, Manga, Manhwa...
  final String status; // Finished, Ongoing...
  final double malScore;
  final Color color; // dominant cover color (AniList provides this later)

  const PickedTitle({
    required this.name,
    required this.isAnime,
    required this.format,
    required this.status,
    required this.malScore,
    required this.color,
  });
}

const List<PickedTitle> kDemoTitles = [
  PickedTitle(
    name: 'Frieren: Beyond Journey\'s End',
    isAnime: true,
    format: 'TV',
    status: 'Finished airing',
    malScore: 9.30,
    color: Color(0xFF5FA8D3),
  ),
  PickedTitle(
    name: 'Steins;Gate',
    isAnime: true,
    format: 'TV',
    status: 'Finished airing',
    malScore: 9.07,
    color: Color(0xFFC9A227),
  ),
  PickedTitle(
    name: 'Vinland Saga',
    isAnime: false,
    format: 'Manga',
    status: 'Finished',
    malScore: 9.02,
    color: Color(0xFFB5502B),
  ),
  PickedTitle(
    name: 'Solo Leveling',
    isAnime: false,
    format: 'Manhwa',
    status: 'Finished',
    malScore: 8.65,
    color: Color(0xFF3B5BDB),
  ),
  PickedTitle(
    name: 'Mob Psycho 100',
    isAnime: true,
    format: 'TV',
    status: 'Finished airing',
    malScore: 8.49,
    color: Color(0xFFD6336C),
  ),
  PickedTitle(
    name: 'Mushishi',
    isAnime: true,
    format: 'TV',
    status: 'Finished airing',
    malScore: 8.65,
    color: Color(0xFF2F9E44),
  ),
];

final _rng = Random();

/// Picks a demo title, never the same one twice in a row.
PickedTitle randomDemoTitle([PickedTitle? previous]) {
  PickedTitle pick;
  do {
    pick = kDemoTitles[_rng.nextInt(kDemoTitles.length)];
  } while (kDemoTitles.length > 1 && identical(pick, previous));
  return pick;
}
