require 'pact/matching_rules/v3/merge'

module Pact
  module MatchingRules
    module V3
      describe Merge do
        subject { Merge.(expected, matching_rules) }

        before do
          allow($stderr).to receive(:puts) do | message |
            raise "Was not expecting stderr to receive #{message.inspect} in this spec. This may be because of a missed rule deletion in Merge."
          end
        end

        describe "no recognised rules" do
          before do
            allow($stderr).to receive(:puts)
          end

          let(:expected) do
            {
              "_links" => {
                "self" => {
                  "href" => "http://localhost:1234/thing"
                }
              }
            }
          end

          let(:matching_rules) do
            {
              "$._links.self.href" => {
                "matchers" => [{ "type" => "unknown" }]
              }
            }
          end

          it "returns the object at that path unaltered" do
            expect(subject["_links"]["self"]["href"]).to eq "http://localhost:1234/thing"
          end

          it "it logs the rules it has ignored" do
            expect($stderr).to receive(:puts) do | message |
              expect(message).to include("WARN")
              expect(message).to include("type")
              expect(message).to include("unknown")
              expect(message).to include("$['_links']")
            end
            subject
          end

        end

        describe "with nil rules" do
          let(:expected) do
            {
              "_links" => {
                "self" => {
                  "href" => "http://localhost:1234/thing"
                }
              }
            }
          end

          let(:matching_rules) { nil }

          it "returns the example unaltered" do
            expect(subject["_links"]["self"]["href"]).to eq "http://localhost:1234/thing"
          end

        end

        describe "type based matching" do
          before do
            allow($stderr).to receive(:puts)
          end

          let(:expected) do
            {
              "name" => "Mary"
            }
          end

          let(:matching_rules) do
            {
              "$.name" => {
                "matchers" => [{ "match" => "type", "ignored" => "matchingrule" }]
              }
            }
          end

          it "creates a SomethingLike at the appropriate path" do
            expect(subject['name']).to be_instance_of(Pact::SomethingLike)
          end

          it "it logs the rules it has ignored" do
            expect($stderr).to receive(:puts).once.with(/ignored.*matchingrule/)
            subject
          end

          it "does not alter the passed in rules hash" do
            original_matching_rules = JSON.parse(matching_rules.to_json)
            subject
            expect(matching_rules).to eq original_matching_rules
          end
        end

        describe "when a Pact.like is nested inside a Pact.each_like which is nested inside a Pact.like" do
          let(:original_definition) do
            Pact.like('foos' => Pact.each_like(Pact.like('name' => "foo1")))
          end

          let(:expected) do
            Pact::Reification.from_term(original_definition)
          end

          let(:matching_rules) do
            Extract.call(original_definition)
          end

          it "creates a Pact::SomethingLike containing a Pact::ArrayLike containing a Pact::SomethingLike" do
            expect(subject.to_hash).to eq original_definition.to_hash
          end
        end

        describe "when a Pact.array_like is the top level object" do
          let(:original_definition) do
            Pact.each_like('foos')
          end

          let(:expected) do
            Pact::Reification.from_term(original_definition)
          end

          let(:matching_rules) do
            Extract.call(original_definition)
          end

          it "creates a Pact::ArrayLike" do
            expect(subject.to_hash).to eq original_definition.to_hash
          end
        end

        describe "when a Pact.like containing an array is the top level object" do
          let(:original_definition) do
            Pact.like(['foos'])
          end

          let(:expected) do
            Pact::Reification.from_term(original_definition).tap { |it| puts it }
          end

          let(:matching_rules) do
            Extract.call(original_definition).tap { |it| puts it }
          end

          it "creates a Pact::SomethingLike" do
            expect(subject).to be_a(Pact::SomethingLike)
            expect(subject.to_hash).to eq original_definition.to_hash
          end
        end

        describe "regular expressions" do
          describe "in a hash" do
            before do
              allow($stderr).to receive(:puts)
            end

            let(:expected) do
              {
                "_links" => {
                  "self" => {
                    "href" => "http://localhost:1234/thing"
                  }
                }
              }
            end

            let(:matching_rules) do
              {
                "$._links.self.href" => {
                  "matchers" => [{ "regex" => "http:\\/\\/.*\\/thing", "match" => "regex", "ignored" => "somerule" }]
                }
              }
            end

            it "creates a Pact::Term at the appropriate path" do
              expect(subject["_links"]["self"]["href"]).to be_instance_of(Pact::Term)
              expect(subject["_links"]["self"]["href"].generate).to eq "http://localhost:1234/thing"
              expect(subject["_links"]["self"]["href"].matcher.inspect).to eq "/http:\\/\\/.*\\/thing/"
            end

            it "it logs the rules it has ignored" do
              expect($stderr).to receive(:puts) do | message |
                expect(message).to match /ignored.*"somerule"/
                expect(message).to_not match /regex/
                expect(message).to_not match /"match"/
              end
              subject
            end
          end

          describe "with an array" do

            let(:expected) do
              {
                "_links" => {
                  "self" => [{
                      "href" => "http://localhost:1234/thing"
                  }]
                }
              }
            end

            let(:matching_rules) do
              {
                "$._links.self[0].href" => {
                  "matchers" => [{ "regex" => "http:\\/\\/.*\\/thing" }]
                }
              }
            end

            it "creates a Pact::Term at the appropriate path" do
              expect(subject["_links"]["self"][0]["href"]).to be_instance_of(Pact::Term)
              expect(subject["_links"]["self"][0]["href"].generate).to eq "http://localhost:1234/thing"
              expect(subject["_links"]["self"][0]["href"].matcher.inspect).to eq "/http:\\/\\/.*\\/thing/"
            end
          end

          describe "with an ArrayLike containing a Term" do
            let(:expected) do
              ["foo"]
            end

            let(:matching_rules) do
              {
                "$" => {"matchers" => [{"min" => 1}]},
                "$[*].*" => {"matchers" => [{"match" => "type"}]},
                "$[*]" => {"matchers" => [{"match" => "regex", "regex"=>"f"}]}
              }
            end

            it "it creates an ArrayLike with a Pact::Term as the contents" do
              expect(subject).to be_a(Pact::ArrayLike)
              expect(subject.contents).to be_a(Pact::Term)
            end
          end
        end

        describe "with an array where all elements should match by type and the rule is specified on the parent element and there is no min specified" do
          let(:expected) do
            {
              'alligators' => [{'name' => 'Mary'}]
            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => {
                "matchers" => [{ 'match' => 'type' }]
              }
            }
          end

          it "creates a Pact::SomethingLike at the appropriate path" do
            expect(subject["alligators"]).to be_instance_of(Pact::SomethingLike)
            expect(subject["alligators"].contents).to eq ['name' => 'Mary']
          end
        end

        describe "with an array where all elements should match by type and the rule is specified on the child elements" do
          let(:expected) do
            {
              'alligators' => [{'name' => 'Mary'}]
            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => {
                "matchers" => [{ 'min' => 2}]
              },
              "$.alligators[*].*" => {
                "matchers" => [{ 'match' => 'type'}]
              }
            }
          end
          it "creates a Pact::ArrayLike at the appropriate path" do
            expect(subject["alligators"]).to be_instance_of(Pact::ArrayLike)
            expect(subject["alligators"].contents).to eq 'name' => 'Mary'
            expect(subject["alligators"].min).to eq 2
          end
        end

        describe "with an array where all elements should match by type and the rule is specified on both the parent element and the child elements" do
          let(:expected) do
            {
              'alligators' => [{'name' => 'Mary'}]
            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => {
                "matchers" => [{ 'min' => 2, 'match' => 'type' }]
              },
              "$.alligators[*].*" => {
                "matchers" => [{ 'match' => 'type' }]
              }
            }
          end

          it "creates a Pact::ArrayLike at the appropriate path" do
            expect(subject["alligators"]).to be_instance_of(Pact::SomethingLike)
            expect(subject["alligators"].contents).to be_instance_of(Pact::ArrayLike)
            expect(subject["alligators"].contents.contents).to eq 'name' => 'Mary'
            expect(subject["alligators"].contents.min).to eq 2
          end
        end

        describe "with an array where all elements should match by type and there is only a match:type on the parent element" do
          let(:expected) do
            {
              'alligators' => [{'name' => 'Mary'}]
            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => { 'matchers' => [{'min' => 2, 'match' => 'type'}] },
            }
          end

          it "creates a Pact::ArrayLike at the appropriate path" do
            expect(subject["alligators"]).to be_instance_of(Pact::ArrayLike)
            expect(subject["alligators"].contents).to eq 'name' => 'Mary'
            expect(subject["alligators"].min).to eq 2
          end
        end

        describe "with an array where all elements should match by type nested inside another array where all elements should match by type" do
          let(:expected) do
            {

              'alligators' => [
                {
                  'name' => 'Mary',
                  'children' => [
                    'age' => 9
                  ]
                }
              ]

            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => { "matchers" => [{ 'min' => 2, 'match' => 'type' }] },
              "$.alligators[*].children" => { "matchers" => [{ 'min' => 1, 'match' => 'type' }]},
            }
          end

          it "creates a Pact::ArrayLike at the appropriate path" do
            expect(subject["alligators"].contents['children']).to be_instance_of(Pact::ArrayLike)
            expect(subject["alligators"].contents['children'].contents).to eq 'age' => 9
            expect(subject["alligators"].contents['children'].min).to eq 1
          end
        end

        describe "with an example array with more than one item" do
          before do
            allow($stderr).to receive(:puts)
          end

          let(:expected) do
            {

              'alligators' => [
                {'name' => 'Mary'},
                {'name' => 'Joe'}
              ]

            }
          end

          let(:matching_rules) do
            {
              "$.alligators" => { "matchers" => [{'min' => 2, 'match' => 'type'}] }
            }
          end

          it "doesn't warn about the min size being ignored" do
            expect(Pact.configuration.error_stream).to receive(:puts).once
            subject
          end

          it "warns that the other items will be ignored" do
            allow(Pact.configuration.error_stream).to receive(:puts)
            expect(Pact.configuration.error_stream).to receive(:puts).with(/WARN: Only the first item/)
            subject
          end
        end

        describe "using bracket notation for a Hash" do
          let(:expected) do
            {
              "name" => "Mary"
            }
          end

          let(:matching_rules) do
            {
              "$['name']" => { "matchers" => [{"match" => "type"}] }
            }
          end

          it "applies the rule" do
            expect(subject['name']).to be_instance_of(Pact::SomethingLike)
          end
        end

        describe "with a dot in the path" do
          let(:expected) do
            {
              "first.name" => "Mary"
            }
          end

          let(:matching_rules) do
            {
              "$['first.name']" => { "matchers" => [{ "match" => "type" }] }
            }
          end

          it "applies the rule" do
            expect(subject['first.name']).to be_instance_of(Pact::SomethingLike)
          end
        end

        describe "with an @ in the path" do
          let(:expected) do
            {
              "@name" => "Mary"
            }
          end

          let(:matching_rules) do
            {
              "$['@name']" => { "matchers" => [ { "match" => "type" }] }
            }
          end

          it "applies the rule" do
            expect(subject['@name']).to be_instance_of(Pact::SomethingLike)
          end
        end

      end
    end
  end
end
