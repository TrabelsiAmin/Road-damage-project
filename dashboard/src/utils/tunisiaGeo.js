/**
 * Deterministic geographic reverse-lookup for Tunisian Governorates,
 * Municipalities, and National Road Corridors without external network APIs.
 */

import { haversineDistanceMeters } from './clustering';

export const ALL_GOVERNORATES = [
  'Tunis',
  'Ariana',
  'Ben Arous',
  'Manouba',
  'Nabeul',
  'Bizerte',
  'Sousse',
  'Sfax',
  'Monastir',
  'Mahdia',
  'Kairouan',
  'Zaghouan',
  'Béja',
  'Jendouba',
  'Le Kef',
  'Siliana',
  'Kasserine',
  'Sidi Bouzid',
  'Gafsa',
  'Tozeur',
  'Kébili',
  'Gabès',
  'Médenine',
  'Tataouine',
];

export const GOVERNORATE_CENTROIDS = {
  Tunis: { lat: 36.8065, lng: 10.1815, municipalities: ['Tunis Ville', 'La Marsa', 'Carthage', 'Le Kram', 'El Menzah', 'Sidi Bou Said', 'La Goulette', 'Le Bardo'] },
  Ariana: { lat: 36.8665, lng: 10.1956, municipalities: ['Ariana Ville', 'La Soukra', 'Raoued', 'Ettadhamen', 'Mnihla', 'Kalaat el-Andalous', 'Sidi Thabet'] },
  'Ben Arous': { lat: 36.7532, lng: 10.2285, municipalities: ['Ben Arous', 'Rades', 'Megrine', 'Hammam Lif', 'Hammam Chott', 'Ezzahra', 'Mornag', 'Bou Mhel'] },
  Manouba: { lat: 36.8080, lng: 10.0900, municipalities: ['Manouba Ville', 'Denden', 'Douar Hicher', 'Oued Ellil', 'Tebourba', 'Mornaguia', 'Borj El Amri'] },
  Nabeul: { lat: 36.4560, lng: 10.7376, municipalities: ['Nabeul', 'Hammamet', 'Kelibia', 'Korba', 'Grombalia', 'Menzel Temime', 'Soliman', 'Dar Chaabane'] },
  Bizerte: { lat: 37.2744, lng: 9.8739, municipalities: ['Bizerte Ville', 'Menzel Bourguiba', 'Mateur', 'Ras Jebel', 'Ghar El Melh', 'Tinja'] },
  Sousse: { lat: 35.8256, lng: 10.6369, municipalities: ['Sousse Ville', 'Hammam Sousse', 'Kalaa Kebira', 'Msaken', 'Akouda', 'Sousse Riadh'] },
  Sfax: { lat: 34.7406, lng: 10.7603, municipalities: ['Sfax Ville', 'Sakiet Ezzit', 'Sakiet Eddaier', 'Thyna', 'El Hencha', 'Agareb'] },
  Monastir: { lat: 35.7770, lng: 10.8260, municipalities: ['Monastir Ville', 'Moknine', 'Ksar Hellal', 'Jemmal', 'Téboulba', 'Sahline'] },
  Mahdia: { lat: 35.5047, lng: 11.0622, municipalities: ['Mahdia Ville', 'Ksour Essef', 'El Jem', 'Chebba', 'Sidi Alouane'] },
  Kairouan: { lat: 35.6781, lng: 10.0963, municipalities: ['Kairouan Ville', 'Bou Hajla', 'Sbikha', 'Haffouz', 'Oueslatia'] },
  Zaghouan: { lat: 36.4029, lng: 10.1429, municipalities: ['Zaghouan', 'Zriba', 'El Fahs', 'Nadhour', 'Bir Mcherga'] },
  'Béja': { lat: 36.7256, lng: 9.1817, municipalities: ['Béja Ville', 'Medjez El Bab', 'Testour', 'Nefza', 'Téboursouk'] },
  Jendouba: { lat: 36.5011, lng: 8.7802, municipalities: ['Jendouba Ville', 'Tabarka', 'Ain Draham', 'Bou Salem', 'Fernana'] },
  'Le Kef': { lat: 36.1742, lng: 8.7049, municipalities: ['Le Kef Ville', 'Dahmani', 'Tajerouine', 'Sers', 'Sakiet Sidi Youssef'] },
  Siliana: { lat: 36.0849, lng: 9.3708, municipalities: ['Siliana Ville', 'Makthar', 'Bou Arada', 'Gaafour', 'El Krib'] },
  Kasserine: { lat: 35.1676, lng: 8.8365, municipalities: ['Kasserine Ville', 'Sbeitla', 'Fériana', 'Thala', 'Sbiba'] },
  'Sidi Bouzid': { lat: 35.0382, lng: 9.4849, municipalities: ['Sidi Bouzid Ville', 'Regueb', 'Jilma', 'Bir El Hafey', 'Menzel Bouzaiane'] },
  Gafsa: { lat: 34.4250, lng: 8.7842, municipalities: ['Gafsa Ville', 'Metlaoui', 'Redeyef', 'Moulares', 'El Ksar'] },
  Tozeur: { lat: 33.9197, lng: 8.1335, municipalities: ['Tozeur Ville', 'Nefta', 'Degache', 'Tameghza'] },
  'Kébili': { lat: 33.7044, lng: 8.9690, municipalities: ['Kébili Ville', 'Douz', 'Souk Lahad', 'El Golâa'] },
  'Gabès': { lat: 33.8815, lng: 10.0982, municipalities: ['Gabès Ville', 'El Hamma', 'Mareth', 'Ghannouch', 'Matmata'] },
  'Médenine': { lat: 33.3549, lng: 10.5055, municipalities: ['Médenine Ville', 'Djerba Houmt Souk', 'Djerba Midoun', 'Zarzis', 'Ben Guerdane'] },
  Tataouine: { lat: 32.9297, lng: 10.4518, municipalities: ['Tataouine Ville', 'Ghomrassen', 'Remada', 'Smâr'] },
};

export const REFERENCE_CORRIDORS = [
  { code: 'A1', name: 'Autoroute A1 (Tunis - Sousse - Sfax)', lat: 36.680, lng: 10.300 },
  { code: 'A4', name: 'Autoroute A4 (Tunis - Bizerte)', lat: 36.950, lng: 10.100 },
  { code: 'RN1', name: 'Route Nationale 1 (Tunis - Ben Arous)', lat: 36.753, lng: 10.228 },
  { code: 'RN8', name: 'Route Nationale 8 (Tunis - Ariana)', lat: 36.866, lng: 10.195 },
  { code: 'RN9', name: 'Route Nationale 9 (Tunis - La Marsa)', lat: 36.851, lng: 10.285 },
  { code: 'RR21', name: 'Route Régionale 21 / Voie Express X', lat: 36.832, lng: 10.154 },
];

/**
 * Resolves an administrative area (Governorate, Municipality, and nearest Corridor)
 * from geographic coordinates (WGS84).
 */
export function resolveTunisiaAdmin(lat, lng) {
  const latitude = Number(lat);
  const longitude = Number(lng);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)) {
    return {
      governorate: 'Non déterminé',
      municipality: 'Non déterminé',
      roadSegment: 'Voie non répertoriée',
      distanceMeters: null,
    };
  }

  // 1. Identify closest governorate centroid
  let bestGov = 'Tunis';
  let minGovDist = Infinity;

  for (const [gov, data] of Object.entries(GOVERNORATE_CENTROIDS)) {
    const dist = haversineDistanceMeters(latitude, longitude, data.lat, data.lng);
    if (dist < minGovDist) {
      minGovDist = dist;
      bestGov = gov;
    }
  }

  // Grand Tunis coastal boundary refinement:
  // Coordinates in the northeast coastal peninsula (La Marsa, Carthage, Gammarth, Sidi Bou Said)
  // belong to Tunis Governorate even if geometrically closer to northern Ariana inland.
  if (latitude >= 36.83 && latitude <= 36.93 && longitude >= 10.28 && longitude <= 10.36) {
    bestGov = 'Tunis';
  }

  // 2. Resolve municipality
  const govData = GOVERNORATE_CENTROIDS[bestGov];
  let municipality = govData?.municipalities?.[0] || bestGov;

  // Granular assignment for Grand Tunis
  if (bestGov === 'Tunis') {
    if (longitude > 10.26 && latitude > 36.83) municipality = 'La Marsa';
    else if (longitude > 10.29 && latitude < 36.87) municipality = 'Carthage';
    else if (latitude > 36.82 && longitude < 10.20) municipality = 'El Menzah';
    else if (latitude < 36.79 && longitude < 10.17) municipality = 'Le Bardo';
    else municipality = 'Tunis Ville';
  } else if (bestGov === 'Ariana') {
    if (longitude > 10.22) municipality = 'La Soukra';
    else if (latitude > 36.90) municipality = 'Raoued';
    else municipality = 'Ariana Ville';
  } else if (bestGov === 'Ben Arous') {
    if (latitude < 36.70) municipality = 'Mornag';
    else if (longitude > 10.25) municipality = 'Rades';
    else if (latitude > 36.76) municipality = 'Megrine';
    else municipality = 'Ben Arous';
  }

  // 3. Resolve closest road corridor
  let bestCorridor = 'Voirie Locale';
  let minCorridorDist = Infinity;

  for (const corr of REFERENCE_CORRIDORS) {
    const d = haversineDistanceMeters(latitude, longitude, corr.lat, corr.lng);
    if (d < minCorridorDist) {
      minCorridorDist = d;
      bestCorridor = corr.name;
    }
  }

  // Only assign corridor name if within reasonable distance (12 km)
  const roadSegment = minCorridorDist <= 12000 ? bestCorridor : `Voirie urbaine (${municipality})`;

  return {
    governorate: bestGov,
    municipality,
    roadSegment,
    distanceMeters: Math.round(minCorridorDist),
  };
}

/**
 * Returns available municipalities for a given governorate.
 */
export function getMunicipalitiesForGovernorate(governorate) {
  if (!governorate || governorate === 'all') return [];
  return GOVERNORATE_CENTROIDS[governorate]?.municipalities || [];
}
