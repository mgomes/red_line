# frozen_string_literal: true

RSpec.describe "Name validation" do
  describe "valid names" do
    it "accepts alphanumeric names" do
      expect { RedLine.bucket("api123", 10, :second) }.not_to raise_error
    end

    it "accepts names with hyphens" do
      expect { RedLine.bucket("my-api", 10, :second) }.not_to raise_error
    end

    it "accepts names with underscores" do
      expect { RedLine.bucket("my_api", 10, :second) }.not_to raise_error
    end

    it "accepts mixed valid characters" do
      expect { RedLine.bucket("My-API_v2", 10, :second) }.not_to raise_error
    end
  end

  describe "invalid names" do
    invalid_names = [
      ["spaces", "my api", "contains space"],
      ["dots", "my.api", "contains dot"],
      ["colons", "my:api", "contains colon"],
      ["slashes", "my/api", "contains slash"],
      ["empty string", "", "empty"],
      ["special chars", "api@v1", "contains @"],
    ]

    invalid_names.each do |description, name, _reason|
      it "rejects names with #{description}" do
        expect { RedLine.bucket(name, 10, :second) }.to raise_error(RedLine::InvalidName) do |error|
          expect(error.name).to eq(name)
        end
      end
    end
  end

  describe "all limiter types validate names" do
    let(:invalid_name) { "invalid name!" }

    it "bucket validates name" do
      expect { RedLine.bucket(invalid_name, 10, :second) }.to raise_error(RedLine::InvalidName)
    end

    it "window validates name" do
      expect { RedLine.window(invalid_name, 10, :second) }.to raise_error(RedLine::InvalidName)
    end

    it "concurrent validates name" do
      expect { RedLine.concurrent(invalid_name, 10) }.to raise_error(RedLine::InvalidName)
    end

    it "leaky validates name" do
      expect { RedLine.leaky(invalid_name, 10, :second) }.to raise_error(RedLine::InvalidName)
    end

    it "points validates name" do
      expect { RedLine.points(invalid_name, 100, 10) }.to raise_error(RedLine::InvalidName)
    end

    it "unlimited does not require a name" do
      expect { RedLine.unlimited }.not_to raise_error
    end
  end
end
