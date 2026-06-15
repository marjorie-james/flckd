# Block all real network connections in the test suite. External data sources
# (Overpass/OSM, open-data portals) are exercised against recorded fixtures via
# WebMock stubs, so tests stay deterministic and never poll a live third party.
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)
