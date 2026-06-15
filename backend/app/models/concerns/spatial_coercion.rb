# Coerces EWKT/WKT string assignments on spatial attributes into RGeo geometry
# objects, so callers (factories, seeds, importers, specs) can assign convenient
# strings like "SRID=4326;POINT(-104.99 39.74)" and still pass geometry
# validations and persist correctly.
#
# Usage:
#   class Camera < ApplicationRecord
#     include SpatialCoercion
#     coerce_spatial :location
#   end
module SpatialCoercion
  extend ActiveSupport::Concern

  # Cartesian (planar) factory matching the `geometry` columns (geographic:
  # false, SRID 4326). A spherical factory would interpret polygon rings as
  # great-circle edges, inverting large lon/lat boxes into their complement.
  EWKT_FACTORY = RGeo::Cartesian.factory(srid: 4326)

  class_methods do
    def coerce_spatial(*attributes)
      attributes.each do |attr|
        define_method("#{attr}=") do |value|
          super(SpatialCoercion.coerce(value))
        end
      end
    end
  end

  # Parses an EWKT/WKT string into an RGeo geometry. Passes through nil and
  # geometries unchanged. Strips a leading "SRID=NNNN;" prefix if present.
  def self.coerce(value)
    return value unless value.is_a?(String)

    wkt = value.sub(/\ASRID=\d+;/i, "")
    EWKT_FACTORY.parse_wkt(wkt)
  rescue RGeo::Error::ParseError, RGeo::Error::InvalidGeometry
    value # leave invalid input alone so validations report it
  end
end
