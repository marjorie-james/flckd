# Base for all JSON serializers. Subclasses wrap a single domain object and
# implement #as_json to shape it into the versioned API contract
# (contracts/openapi.yaml). Keeps serialization a single-responsibility concern,
# separate from controllers and models (Constitution Principle I).
class ApplicationSerializer
  def initialize(object)
    @object = object
  end

  def as_json(*)
    raise NotImplementedError, "#{self.class} must implement #as_json"
  end
end
