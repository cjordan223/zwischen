# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Zwischen::Reporter::Sarif do
  def build_finding(severity: "high", file: "/project/app/code.rb", line: 12,
                    rule_id: "aws-access-token", raw_data: {})
    Zwischen::Finding::Finding.new(
      type: "secret",
      scanner: "gitleaks",
      severity: severity,
      file: file,
      line: line,
      message: "AWS key detected",
      rule_id: rule_id,
      raw_data: raw_data
    )
  end

  def render(findings, project_root: "/project")
    JSON.parse(described_class.report({ findings: findings }, project_root: project_root))
  end

  it "produces a valid SARIF 2.1.0 envelope" do
    sarif = render([build_finding])

    expect(sarif["version"]).to eq("2.1.0")
    expect(sarif["$schema"]).to include("sarif-schema-2.1.0")
    driver = sarif["runs"].first["tool"]["driver"]
    expect(driver["name"]).to eq("Zwischen")
    expect(driver["version"]).to eq(Zwischen::VERSION)
  end

  it "maps findings to results with relative URIs and severity levels" do
    sarif = render([build_finding(severity: "critical"), build_finding(severity: "medium", line: 3)])

    results = sarif["runs"].first["results"]
    expect(results.length).to eq(2)
    expect(results[0]["level"]).to eq("error")
    expect(results[1]["level"]).to eq("warning")
    location = results[0]["locations"].first["physicalLocation"]
    expect(location["artifactLocation"]["uri"]).to eq("app/code.rb")
    expect(location["region"]["startLine"]).to eq(12)
  end

  it "deduplicates rules and tags them with security severity" do
    sarif = render([build_finding, build_finding(line: 99)])

    rules = sarif["runs"].first["tool"]["driver"]["rules"]
    expect(rules.length).to eq(1)
    expect(rules.first["id"]).to eq("aws-access-token")
    expect(rules.first["properties"]["security-severity"]).to eq("8.0")
  end

  it "appends AI fix suggestions to the result message" do
    finding = build_finding(raw_data: { "ai_fix_suggestion" => "Rotate the key." })

    message = render([finding])["runs"].first["results"].first["message"]["text"]
    expect(message).to include("AWS key detected")
    expect(message).to include("Fix: Rotate the key.")
  end

  it "defaults a missing line to 1 and leaves foreign paths untouched" do
    finding = build_finding(file: "/elsewhere/x.rb", line: nil)

    result = render([finding])["runs"].first["results"].first
    expect(result["locations"].first["physicalLocation"]["artifactLocation"]["uri"]).to eq("/elsewhere/x.rb")
    expect(result["locations"].first["physicalLocation"]["region"]["startLine"]).to eq(1)
  end

  it "renders an empty runs.results array when there are no findings" do
    sarif = render([])
    expect(sarif["runs"].first["results"]).to eq([])
    expect(sarif["runs"].first["tool"]["driver"]["rules"]).to eq([])
  end
end
