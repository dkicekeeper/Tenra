// Cases of the valuation eval (eval/valuation.ts, docs/plan-assets-roadmap.md §3, A6): an asset
// as the phone sends it and a reference value, with where the reference comes from and when.
// References are independent of the search being graded where possible: official statistics
// (the Bureau of National Statistics of Kazakhstan, ONS and HM Land Registry), market reports
// (idealista, Endeksa, hepsiemlak) and price guides (KBB, CarGurus); a few are medians of
// listings read by hand. Market prices move: refresh a reference older than about three months,
// and widen nothing to make a case pass.
//
// Rooms are counted as the country's listings count them: rooms in Kazakhstan, bedrooms in the
// UK, the US and Spain, the first number of "2+1" in Turkey.

import type { AssetDescription } from "../src/valuation";

export type ValuationExpectation =
  | { status: "ok"; currency: string; value: number; tolerance: number; source: string; asOf: string }
  | { status: "insufficient"; source: string };

export interface ValuationCase {
  id: string;
  asset: AssetDescription;
  expect: ValuationExpectation;
}

export const VALUATION_CASES: ValuationCase[] = [
  {
    id: "kz-almaty-flat-2r",
    asset: { kind: "apartment", country: "KZ", city: "Алматы", district: "Бостандыкский", area_m2: 65, rooms: 2, year_built: 2015, building: "monolith", floor: 7, floors: 12, condition: "good" },
    expect: {
      status: "ok",
      currency: "KZT",
      value: 50_300_000,
      tolerance: 0.15,
      source: "BNS: resale in Almaty 756 164 KZT/m2 (September 2026); six two-room listings of the Bostandyk district, median 773 511 KZT/m2",
      asOf: "2026-11-02",
    },
  },
  {
    id: "kz-astana-flat-1r",
    asset: { kind: "apartment", country: "KZ", city: "Астана", district: "Есильский", area_m2: 42, rooms: 1, year_built: 2020, building: "monolith" },
    expect: { status: "ok", currency: "KZT", value: 31_100_000, tolerance: 0.2, source: "BNS: resale in Astana 741 532 KZT/m2 (September 2026)", asOf: "2026-10-09" },
  },
  {
    id: "kz-shymkent-flat-3r",
    asset: { kind: "apartment", country: "KZ", city: "Шымкент", area_m2: 80, rooms: 3, year_built: 2012, building: "brick" },
    expect: { status: "ok", currency: "KZT", value: 37_600_000, tolerance: 0.2, source: "BNS: resale in Shymkent 469 665 KZT/m2 (September 2026)", asOf: "2026-10-09" },
  },
  {
    id: "kz-karaganda-flat-2r-panel",
    // The app's form asks for the district: without it the search found mostly Maikuduk, the
    // cheapest part of the city (run 120).
    asset: { kind: "apartment", country: "KZ", city: "Караганда", district: "Казыбек би", area_m2: 48, rooms: 2, year_built: 1975, building: "panel", condition: "standard" },
    expect: {
      status: "ok",
      currency: "KZT",
      value: 19_100_000,
      tolerance: 0.25,
      source: "Four old-stock two-room listings of the Kazybek bi district read by hand, median 397 thousand KZT/m2; BNS resale in Karaganda 408 119 KZT/m2 (September 2026)",
      asOf: "2026-11-02",
    },
  },
  {
    id: "kz-camry-2019",
    asset: { kind: "vehicle", country: "KZ", city: "Алматы", make: "Toyota", model: "Camry", generation: "XV70", year: 2019, engine_l: 2.5, fuel: "petrol", transmission: "automatic", mileage_km: 110_000, customs_cleared: true },
    expect: { status: "ok", currency: "KZT", value: 13_350_000, tolerance: 0.12, source: "Six 2019 listings on Kolesa.kz and elsewhere, 12.5-13.9 million, median 13.35 million", asOf: "2026-11-02" },
  },
  {
    id: "kz-cobalt-2022",
    asset: { kind: "vehicle", country: "KZ", city: "Шымкент", make: "Chevrolet", model: "Cobalt", year: 2022, engine_l: 1.5, fuel: "petrol", transmission: "automatic", mileage_km: 80_000, customs_cleared: true },
    expect: { status: "ok", currency: "KZT", value: 5_000_000, tolerance: 0.15, source: "Kolesa.kz: 2022 automatics with 68-114 thousand km in Shymkent at 4.8-5.2 million", asOf: "2026-11-02" },
  },
  {
    id: "kz-land-kaskelen-10",
    asset: { kind: "land", country: "KZ", city: "Каскелен", region: "Алматинская область", land_ares: 10, land_use: "residential", utilities: ["electricity", "water"] },
    expect: { status: "ok", currency: "KZT", value: 15_500_000, tolerance: 0.3, source: "Listings of 10-sotka residential plots in Kaskelen at 15.5-17 million (October 2026); land prices spread widely", asOf: "2026-11-02" },
  },
  {
    id: "tr-istanbul-kadikoy-2-1",
    asset: { kind: "apartment", country: "TR", city: "İstanbul", district: "Kadıköy", area_m2: 100, rooms: 2, year_built: 2010 },
    expect: {
      status: "ok",
      currency: "TRY",
      value: 16_000_000,
      tolerance: 0.2,
      source: "Kadıköy asking prices per m2: hepsiemlak 158 374 TRY, Endeksa 172 741 TRY (September 2026)",
      asOf: "2026-11-02",
    },
  },
  {
    id: "es-madrid-chamberi",
    asset: { kind: "apartment", country: "ES", city: "Madrid", district: "Chamberí", area_m2: 80, rooms: 2 },
    expect: { status: "ok", currency: "EUR", value: 775_000, tolerance: 0.15, source: "idealista: two-bedroom listings in Chamberí at 9 684 EUR/m2 on average (the district's all flats: 9 159)", asOf: "2026-11-02" },
  },
  {
    id: "gb-london-lewisham",
    asset: { kind: "apartment", country: "GB", city: "London", district: "Lewisham", area_m2: 65, rooms: 2 },
    expect: {
      status: "ok",
      currency: "GBP",
      value: 400_000,
      tolerance: 0.2,
      source: "ONS and HM Land Registry: flats and maisonettes sold in Lewisham at 374 000 GBP on average (August 2026, provisional); two-bedroom asking prices sit above",
      asOf: "2026-11-02",
    },
  },
  {
    id: "de-golf-2018",
    asset: { kind: "vehicle", country: "DE", city: "Berlin", make: "Volkswagen", model: "Golf", generation: "VII", year: 2018, engine_l: 1.5, fuel: "petrol", mileage_km: 80_000 },
    expect: { status: "ok", currency: "EUR", value: 17_500, tolerance: 0.15, source: "mobile.de: Golf VII 1.5 TSI of 2018-2019 with 100-113 thousand km at 17 950-17 990 EUR", asOf: "2026-11-02" },
  },
  {
    id: "us-civic-2019",
    asset: { kind: "vehicle", country: "US", city: "Columbus", region: "Ohio", make: "Honda", model: "Civic", generation: "LX sedan", year: 2019, fuel: "petrol", transmission: "automatic", mileage_km: 96_500 },
    expect: {
      status: "ok",
      currency: "USD",
      value: 16_500,
      tolerance: 0.15,
      source: "KBB: 2019 Civic LX resale 14 400 USD; CarGurus: 2019 Civic average listing 17 122 USD; Edmunds: an LX with 72 thousand miles at 17 998 USD",
      asOf: "2026-11-02",
    },
  },
  {
    id: "kz-other-handmade",
    asset: { kind: "other", country: "KZ", city: "Костанай", description: "Резная деревянная шкатулка ручной работы, авторская", year: 2015 },
    expect: { status: "insufficient", source: "A one-off handmade thing has no comparable listings: the honest answer is too few" },
  },
];
