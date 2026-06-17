FactoryBot.define do
  factory :data_source do
    sequence(:name) { |n| "source-#{n}" }
    kind { "community" }
  end

  factory :camera do
    association :data_source
    sequence(:external_ref) { |n| "ext-#{n}" }
    # Denver-ish coordinates by default.
    location { "SRID=4326;POINT(-104.9903 39.7392)" }
    camera_type { "Flock" }
    confidence { 0.9 }
    verification_status { "unverified" }
    first_seen_at { Time.current }

    trait :verified do
      verification_status { "verified" }
      last_verified_at { Time.current }
    end

    trait :removed do
      verification_status { "removed" }
    end

    trait :disputed do
      verification_status { "disputed" }
    end
  end

  factory :monitored_segment do
    association :camera
    osm_way_id { 12_345 }
    geometry { "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)" }
    direction { "both" }
    snap_distance_m { 3.0 }
  end

  factory :coverage_area do
    sequence(:name) { |n| "Area #{n}" }
    region { "SRID=4326;MULTIPOLYGON(((-125 24, -66 24, -66 49, -125 49, -125 24)))" }
    data_freshness_at { Time.current }
  end
end
