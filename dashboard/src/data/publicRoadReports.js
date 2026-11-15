/**
 * External public reports of road damage in Tunisia.
 * These are not TariqMap captures and must not be written as observations.
 * Coordinates, when present, are place centroids from Nominatim (queried
 * 2026-11-15), never a measured damage point. The source pages below were opened.
 */

export const PUBLIC_ROAD_REPORTS = [
  {
    id: 'oued-el-khayat-2026',
    title: "Effondrement de la route d'Oued El Khayat",
    place: "Jaafar, délégation de Raoued ; route d'Oued El Khayat (La Presse écrit aussi Boujaafar, gouvernorat de l'Ariana)",
    dateLabel: '21 septembre 2026',
    dateNote: {
      fr: "Date de l'article et de la déclaration du ministère. La Presse situe les dégâts « la semaine dernière » ; Business News écrit que le ministère suivait la situation « depuis samedi », sans autre date.",
      en: "Date of the article and of the ministry statement. La Presse places the damage “last week”; Business News says the ministry had been following the situation “since Saturday”, with no other date.",
    },
    quote: "l'effondrement d'une partie de la chaussée à Jaafar",
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'Business News',
        url: 'https://businessnews.com.tn/2026/09/21/effondrement-de-la-route-doued-el-khayat-le-ministere-de-lequipement-sexplique/1419358/',
      },
      {
        name: 'La Presse de Tunisie',
        url: 'https://www.lapresse.tn/2026/09/21/voirie-endommagee-a-lariana-quand-la-pluie-met-a-nu-la-fragilite-des-routes/',
      },
    ],
    locations: [
      {
        id: 'jaafar-raoued',
        place: 'Jaafar, délégation de Raoued',
        precision: 'approximate-centroid',
        lat: 36.9156857,
        lng: 10.1826972,
        positionLabel: {
          fr: "Position approximative : centroïde administratif de Jaafar (Raoued, Ariana) renvoyé par Nominatim. Ce n'est pas le point de l'effondrement.",
          en: 'Approximate position: administrative centroid of Jaafar (Raoued, Ariana) returned by Nominatim. This is not the collapse point.',
        },
        geocoderName: 'Nominatim / OpenStreetMap',
        geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=Jaafar%2C+Raoued%2C+Ariana%2C+Tunisia&format=jsonv2&countrycodes=tn',
      },
    ],
  },
  {
    id: 'sfax-perimetre-2026-08',
    title: 'Nids-de-poule et fissures dans le périmètre municipal de Sfax',
    place: 'axes principaux et secondaires du périmètre municipal de Sfax',
    dateLabel: '27 août 2026',
    dateNote: {
      fr: "Date de la dépêche. La source ne donne pas de jour distinct pour chaque dégradation.",
      en: 'Date of the dispatch. The source does not give a separate day for each defect.',
    },
    quote: 'réfection des nids-de-poule et fissures',
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'Directinfo (avec TAP)',
        url: 'https://directinfo.webmanagercenter.com/2026/08/27/sfax-la-municipalite-lance-des-travaux-pour-reparer-les-nids-de-poule-et-fissures/',
      },
    ],
    unmappedNote: {
      fr: "Pas sur la carte : la source couvre le périmètre municipal, sans rue ni coordonnées. Le centre de Sfax n'est pas utilisé comme point de dégradation.",
      en: 'Not on the map: the source covers the municipal area, with no street and no coordinates. Central Sfax is not used as a damage point.',
    },
  },
  {
    id: 'sfax-rues-2026-06',
    title: 'Nids-de-poule et fissures signalés par la municipalité de Sfax',
    place: "rues Lattaquié, Palestine et Ahmed El Ferati, arrondissement d'El Bostane ; rue Mohamed Masmoudi, arrondissement de la Médina ; rue Assouan, embranchement de la rocade n°5 ; rue Nizar Kabbani ; rue Abdelmajid Snoussi ; voie menant à l'Institut Abou Al-Hassan El Lakhmi, arrondissement de Hay Habib ; abords de la piscine municipale et du commissariat régional à l'éducation",
    dateLabel: '21 juin 2026',
    dateNote: {
      fr: "Date de l'article. Les interventions sont situées « au cours de cette semaine », sans jour précis.",
      en: 'Date of the article. The work is placed “during this week”, with no exact day.',
    },
    quote: 'réparation des nids-de-poule et des fissures',
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'Tunisie Numérique',
        url: 'https://www.tunisienumerique.com/sfax-poursuite-des-travaux-de-reparation-des-routes-sur-plusieurs-axes/',
      },
    ],
    placementExtra: {
      fr: "Les autres rues citées dans le même article ne sont pas placées : aucun centroïde de voie n'a été retenu.",
      en: 'The other streets named in the same article are not placed: no street centroid was kept.',
    },
    locations: [
      {
        id: 'rue-palestine-bostane',
        place: "rue Palestine, arrondissement d'El Bostane",
        precision: 'approximate-centroid',
        lat: 34.7521432,
        lng: 10.7674612,
        positionLabel: {
          fr: "Position approximative : centroïde de la rue Palestine à El Bostane (Sfax) renvoyé par Nominatim. Ce n'est pas l'emplacement d'un défaut mesuré.",
          en: 'Approximate position: centroid of Rue Palestine in El Bostane (Sfax) returned by Nominatim. This is not a measured defect location.',
        },
        geocoderName: 'Nominatim / OpenStreetMap',
        geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=%D9%86%D9%87%D8%AC+%D9%81%D9%84%D8%B3%D8%B7%D9%8A%D9%86+%D8%A7%D9%84%D8%A8%D8%B3%D8%AA%D8%A7%D9%86+%D8%B5%D9%81%D8%A7%D9%82%D8%B3&format=jsonv2&countrycodes=tn',
      },
    ],
  },
  {
    id: 'moulares-2025',
    title: 'Crevasses et nids-de-poule à Moularès',
    place: 'Moularès ; la principale voie de circulation de la ville',
    dateLabel: '19 octobre 2025',
    dateNote: {
      fr: "Date de l'article. La source décrit un état durable, pas un jour d'apparition.",
      en: 'Date of the article. The source describes an ongoing condition, not a day when it appeared.',
    },
    quote: 'crevasses et des nids-de-poule',
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'La Presse de Tunisie',
        url: 'https://www.lapresse.tn/2025/10/19/moulares-la-voix-des-citoyens-face-a-une-infrastructure-defectueuse/',
      },
    ],
    placementExtra: {
      fr: "La source ne nomme pas la rue : le marqueur est le centroïde de la ville.",
      en: 'The source does not name the street: the marker is the town centroid.',
    },
    locations: [
      {
        id: 'moulares-ville',
        place: 'Moularès',
        precision: 'approximate-centroid',
        lat: 34.4857370,
        lng: 8.2733836,
        positionLabel: {
          fr: "Position approximative : centroïde de la ville de Moularès (Gafsa) renvoyé par Nominatim. La source ne nomme pas la rue.",
          en: 'Approximate position: centroid of the town of Moularès (Gafsa) returned by Nominatim. The source does not name the street.',
        },
        geocoderName: 'Nominatim / OpenStreetMap',
        geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=Moular%C3%A8s%2C+Gafsa%2C+Tunisia&format=jsonv2&countrycodes=tn',
      },
    ],
  },
  {
    id: 'a1-pk69-84-2025',
    title: 'Fissures et affaissements sur l’autoroute A1',
    place: 'autoroute A1 (PK 69 – PK 84), axe Sousse – Tunis',
    dateLabel: '11 septembre 2025',
    dateNote: {
      fr: "Date de publication du droit de réponse. La source ne date pas l'apparition des dégradations.",
      en: 'Publication date of the right of reply. The source does not date when the damage appeared.',
    },
    quote: 'fissures, affaissements, perte d’adhérence',
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'Tunisie Numérique (droit de réponse de Tunisie Autoroutes)',
        url: 'https://www.tunisienumerique.com/droit-de-reponse-de-tunisie-autoroutes/',
      },
    ],
    unmappedNote: {
      fr: 'Pas sur la carte : la source indique des points kilométriques, pas des coordonnées.',
      en: 'Not on the map: the source gives kilometer points, not coordinates.',
    },
  },
  {
    id: 'kabaria-2020',
    title: 'Affaissement d’une route à Kabaria',
    place: 'quartier Kabaria, au sud de Tunis',
    dateLabel: '10 septembre 2020',
    dateNote: {
      fr: "L'article du 11 septembre 2020 situe l'affaissement dans l'après-midi du jeudi 10 septembre 2020. La profondeur citée (« trou de 6 mètres ») vient d'un message Facebook repris par Kapitalis, pas d'un relevé TariqMap.",
      en: 'The 11 September 2020 article places the collapse on the afternoon of Thursday 10 September 2020. The quoted depth (“6-metre hole”) comes from a Facebook post relayed by Kapitalis, not a TariqMap survey.',
    },
    quote: "affaissement d'une route",
    publicNote: {
      fr: 'Rapport public, pas une capture TariqMap.',
      en: 'Public report, not a TariqMap capture.',
    },
    sources: [
      {
        name: 'Kapitalis',
        url: 'https://kapitalis.com/tunisie/2020/09/11/pluies-a-tunis-une-voiture-tombe-dans-un-trou-cause-par-laffaissement-dune-route-a-kabaria/',
      },
    ],
    locations: [
      {
        id: 'kabaria',
        place: 'quartier Kabaria',
        precision: 'approximate-centroid',
        lat: 36.7422859,
        lng: 10.1918110,
        positionLabel: {
          fr: "Position approximative : centroïde du quartier Kabaria (Tunis) renvoyé par Nominatim. Ce n'est pas le point du trou.",
          en: 'Approximate position: centroid of the Kabaria district (Tunis) returned by Nominatim. This is not the hole’s point.',
        },
        geocoderName: 'Nominatim / OpenStreetMap',
        geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=Kabaria%2C+Tunis%2C+Tunisia&format=jsonv2&countrycodes=tn',
      },
    ],
  },
];
