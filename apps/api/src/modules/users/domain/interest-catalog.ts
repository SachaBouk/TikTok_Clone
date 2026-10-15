// Catalogue des centres d'intérêt (ADR-055), dans le code comme celui des cadeaux : un changement passe par un
// déploiement. Les codes sont stables (gardés en base) ; un code retiré du catalogue est ignoré à la lecture.
// Choisis à l'inscription, ils n'ont pas encore d'effet sur le feed (algorithme For You reporté, ADR-016).
export interface Interest {
  code: string;
  name: string;
  emoji: string;
}

export const INTEREST_CATALOG: readonly Interest[] = [
  { code: 'animals', name: 'Animaux', emoji: '🐱' },
  { code: 'comedy', name: 'Humour', emoji: '🤣' },
  { code: 'travel', name: 'Voyage', emoji: '🏝️' },
  { code: 'food', name: 'Cuisine', emoji: '🍔' },
  { code: 'sports', name: 'Sport', emoji: '🏀' },
  { code: 'beauty_style', name: 'Beauté et mode', emoji: '💄' },
  { code: 'art', name: 'Art', emoji: '🎨' },
  { code: 'gaming', name: 'Jeux vidéo', emoji: '🎮' },
  { code: 'science_education', name: 'Sciences et éducation', emoji: '🧐' },
  { code: 'dance', name: 'Danse', emoji: '💃' },
  { code: 'diy', name: 'DIY', emoji: '✂️' },
  { code: 'auto', name: 'Auto et moto', emoji: '🏍️' },
  { code: 'music', name: 'Musique', emoji: '🎵' },
  { code: 'life_hacks', name: 'Astuces', emoji: '💡' },
  { code: 'oddly_satisfying', name: 'Satisfaisant', emoji: '🤯' },
  { code: 'outdoors', name: 'Plein air', emoji: '🧗' },
  { code: 'fandom', name: 'Fandoms', emoji: '🦸' },
];

const INTEREST_CODES: ReadonlySet<string> = new Set(INTEREST_CATALOG.map((interest) => interest.code));

export function isInterestCode(code: string): boolean {
  return INTEREST_CODES.has(code);
}

// Codes connus parmi `codes`, sans doublon, dans l'ordre du catalogue.
export function inCatalogOrder(codes: Iterable<string>): string[] {
  const chosen = new Set(codes);
  return INTEREST_CATALOG.filter((interest) => chosen.has(interest.code)).map((interest) => interest.code);
}
