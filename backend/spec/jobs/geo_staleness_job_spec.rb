require "rails_helper"

RSpec.describe GeoStalenessJob, type: :job do
  it "runs the geo substrate freshness check" do
    checker = instance_double(Geo::SubstrateFreshness)
    allow(Geo::SubstrateFreshness).to receive(:new).and_return(checker)
    expect(checker).to receive(:check)

    described_class.new.perform
  end
end
