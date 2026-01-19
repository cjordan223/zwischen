# frozen_string_literal: true

require "spec_helper"
require "zwischen/scanner/base"

RSpec.describe Zwischen::Scanner::Base do
  let(:scanner) { described_class.new(name: "test", command: "test-cmd") }

  describe "#executable_path" do
    it "finds local executable first" do
      local_path = File.join(Zwischen::Scanner::Base::ZWISCHEN_BIN_DIR, "test-cmd")
      allow(File).to receive(:executable?).with(local_path).and_return(true)
      
      expect(scanner.executable_path).to eq(local_path)
    end

    it "falls back to system PATH" do
      local_path = File.join(Zwischen::Scanner::Base::ZWISCHEN_BIN_DIR, "test-cmd")
      allow(File).to receive(:executable?).with(local_path).and_return(false)
      allow(scanner).to receive(:system).with("which", "test-cmd", any_args).and_return(true)
      
      expect(scanner.executable_path).to eq("test-cmd")
    end

    it "returns nil if not found" do
      local_path = File.join(Zwischen::Scanner::Base::ZWISCHEN_BIN_DIR, "test-cmd")
      allow(File).to receive(:executable?).with(local_path).and_return(false)
      allow(scanner).to receive(:system).with("which", "test-cmd", any_args).and_return(false)
      
      expect(scanner.executable_path).to be_nil
    end
  end

  describe "#available?" do
    it "is true when executable exists" do
      allow(scanner).to receive(:executable_path).and_return("/usr/bin/test-cmd")
      expect(scanner.available?).to be true
    end

    it "is false when executable is missing" do
      allow(scanner).to receive(:executable_path).and_return(nil)
      expect(scanner.available?).to be false
    end
  end
end
