require "rails_helper"
require "yaml"

# Contract test (T025): validates that real API responses conform to the
# versioned OpenAPI contract in contracts/openapi.yaml (Constitution Principle
# III — human/machine parity, versioned contracts). Geo services are stubbed so
# the suite stays deterministic (Principle II); we assert response SHAPE, not
# live engine behavior.
RSpec.describe "OpenAPI contract", type: :request do
  # Resolve the contract from the first path that exists: an explicit override,
  # the read-only mount inside the Docker test container (see docker-compose), or
  # the repo-relative location when running on a host with the full tree.
  spec_path = [
    ENV["OPENAPI_CONTRACT"],
    "/contracts/openapi.yaml",
    Rails.root.join("..", "specs", "002-flock-route-avoidance", "contracts", "openapi.yaml").to_s
  ].compact.find { |p| File.exist?(p) }

  let(:spec) { YAML.safe_load_file(spec_path, permitted_classes: [], aliases: false) }

  # Minimal JSON-Schema (OpenAPI 3.1 subset) validator: resolves $ref against
  # the document's components and recursively checks types/required/enum. Extra
  # properties are permitted (OpenAPI default). Returns a list of error strings.
  def schema_errors(value, schema, root, path = "$")
    schema = resolve_ref(schema, root)
    return [] if schema.nil?

    return [] if value.nil? && (schema["nullable"] || Array(schema["enum"]).include?(nil))

    case schema["type"]
    when "object"
      return [ "#{path}: expected object, got #{value.class}" ] unless value.is_a?(Hash)

      errors = []
      Array(schema["required"]).each do |key|
        errors << "#{path}.#{key}: required but missing" unless value.key?(key.to_s)
      end
      (schema["properties"] || {}).each do |key, prop_schema|
        next unless value.key?(key.to_s)

        errors.concat(schema_errors(value[key.to_s], prop_schema, root, "#{path}.#{key}"))
      end
      errors
    when "array"
      return [ "#{path}: expected array, got #{value.class}" ] unless value.is_a?(Array)

      value.each_with_index.flat_map { |item, i| schema_errors(item, schema["items"], root, "#{path}[#{i}]") }
    when "string"
      type_error(value, String, "string", path) + enum_error(value, schema, path)
    when "integer"
      type_error(value, Integer, "integer", path) + enum_error(value, schema, path)
    when "number"
      type_error(value, Numeric, "number", path) + enum_error(value, schema, path)
    when "boolean"
      [ true, false ].include?(value) ? [] : [ "#{path}: expected boolean, got #{value.inspect}" ]
    else
      [] # untyped (e.g. free-form details object) — accept anything
    end
  end

  def resolve_ref(schema, root)
    return schema unless schema.is_a?(Hash) && schema["$ref"]

    pointer = schema["$ref"].delete_prefix("#/").split("/")
    root.dig(*pointer)
  end

  def type_error(value, klass, name, path)
    value.is_a?(klass) ? [] : [ "#{path}: expected #{name}, got #{value.inspect}" ]
  end

  def enum_error(value, schema, path)
    return [] unless schema["enum"]
    return [] if schema["enum"].include?(value)

    [ "#{path}: #{value.inspect} not in enum #{schema['enum'].inspect}" ]
  end

  def response_schema(path, http_method, status = "200")
    schema = spec.dig("paths", path, http_method, "responses", status.to_s, "content", "application/json", "schema")
    raise "no #{status} schema for #{http_method.upcase} #{path}" if schema.nil?

    schema
  end

  def expect_conforms(path, http_method)
    errors = schema_errors(response.parsed_body, response_schema(path, http_method), spec)
    expect(errors).to be_empty, "Response violated #{http_method.upcase} #{path} contract:\n#{errors.join("\n")}"
  end

  # --- Geo service stubs (deterministic) ---------------------------------------

  def stub_planner
    result = Routing::Result.new(
      geometry: "_poly_", distance_m: 6_000, duration_s: 600,
      maneuvers: [ { type: "start", localized_text: "Head north", distance_m: 6_000,
                    location: { lat: 39.74, lng: -104.99 } } ],
      cameras_avoided_count: 2, remaining_cameras: [ { osm_way_id: 999, location: { lat: 39.7, lng: -104.9 } } ],
      is_fully_clean: true,
      fastest_comparison: { distance_m: 5_000, duration_s: 500, added_distance_m: 1_000, added_duration_s: 100 },
      coverage_warning: nil
    )
    allow(Routing::RoutePlanner).to receive(:new).and_return(instance_double(Routing::RoutePlanner, plan: result))
  end

  def stub_geocoder
    geocode_result = { "label" => "1600 Glenarm Pl, Denver", "coordinates" => { "lat" => 39.74, "lng" => -104.99 },
                       "type" => "address", "confidence" => 0.9 }
    fake = double("Geocoder", search: [ geocode_result ], reverse: geocode_result)
    allow(Geocoding::GeocoderClient).to receive(:build).and_return(fake)
  end

  it "POST /routes conforms to the Route schema" do
    stub_planner
    post "/api/v1/routes",
         params: { route: { origin: { lat: 39.7392, lng: -104.9903 },
                            destination: { lat: 39.7294, lng: -104.8319 } } },
         as: :json
    expect(response).to have_http_status(:ok)
    expect_conforms("/routes", "post")
  end

  it "GET /geocode/search conforms" do
    stub_geocoder
    get "/api/v1/geocode/search", params: { q: "glenarm" }
    expect(response).to have_http_status(:ok)
    expect_conforms("/geocode/search", "get")
  end

  it "POST /geocode/reverse conforms" do
    stub_geocoder
    post "/api/v1/geocode/reverse", params: { coordinate: { lat: 39.74, lng: -104.99 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect_conforms("/geocode/reverse", "post")
  end

  it "GET /cameras conforms" do
    create(:camera, location: "SRID=4326;POINT(-104.99 39.74)", confidence: 0.9)
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8" }
    expect(response).to have_http_status(:ok)
    expect_conforms("/cameras", "get")
  end

  it "GET /coverage conforms" do
    create(:coverage_area)
    get "/api/v1/coverage", params: { lat: 39.74, lng: -104.99 }
    expect(response).to have_http_status(:ok)
    expect_conforms("/coverage", "get")
  end

  it "GET /meta/locales conforms" do
    get "/api/v1/meta/locales"
    expect(response).to have_http_status(:ok)
    expect_conforms("/meta/locales", "get")
  end
end
