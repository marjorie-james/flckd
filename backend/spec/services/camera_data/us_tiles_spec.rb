require "rails_helper"

RSpec.describe CameraData::Sources::UsTiles do
  it "tiles the continental US into valid cells covering the CONUS bounds" do
    cells = described_class.cells(cell_deg: 5.0)

    expect(cells).not_to be_empty
    cells.each do |c|
      expect(c[:south]).to be < c[:north]
      expect(c[:west]).to be < c[:east]
    end

    conus = described_class::CONUS
    expect(cells.map { |c| c[:south] }.min).to eq(conus[:south])
    expect(cells.map { |c| c[:west] }.min).to eq(conus[:west])
    expect(cells.map { |c| c[:north] }.max).to eq(conus[:north])
    expect(cells.map { |c| c[:east] }.max).to eq(conus[:east])
  end

  it "produces more cells with a smaller cell size" do
    expect(described_class.cells(cell_deg: 2.0).size).to be > described_class.cells(cell_deg: 10.0).size
  end
end
