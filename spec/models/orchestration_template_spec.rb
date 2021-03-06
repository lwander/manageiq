require "spec_helper"

describe OrchestrationTemplate do
  describe ".find_or_create_by_contents" do
    context "when the template does not exist" do
      let(:query_hash) { FactoryGirl.build(:orchestration_template).as_json.symbolize_keys }

      it "creates a new template" do
        expect(OrchestrationTemplate.count).to eq(0)
        record = OrchestrationTemplate.find_or_create_by_contents(query_hash)[0]
        expect(OrchestrationTemplate.count).to eq(1)
        expect(record.name).to eq(query_hash[:name])
        expect(record.content).to eq(query_hash[:content])
        expect(record.description).to eq(query_hash[:description])
        expect(record.md5).not_to be_nil
      end
    end

    context "when the template already exists" do
      before do
        @existing_record = FactoryGirl.create(:orchestration_template)
        # prepare the query with different name and description; it is considered the same template
        # because the body (:template and :md5) does not change
        @query_hash = @existing_record.as_json.symbolize_keys.except(:id)
        @query_hash[:name]        = "renamed"
        @query_hash[:description] = "modified description"
      end

      it "finds the existing template regardless the new name or description" do
        expect(OrchestrationTemplate.count).to eq(1)
        expect(@existing_record).to eq(OrchestrationTemplate.find_or_create_by_contents(@query_hash)[0])
        expect(OrchestrationTemplate.count).to eq(1)
      end

      it "creates a draft template even though the content is a duplicate" do
        expect(OrchestrationTemplate.count).to eq(1)
        @query_hash[:draft] = true
        expect(@existing_record).not_to eq(OrchestrationTemplate.find_or_create_by_contents(@query_hash)[0])
        expect(OrchestrationTemplate.count).to eq(2)
      end
    end
  end

  context "when both types of templates, either alone or with deployed stacks, are present" do
    before do
      # prepare a mini environment with an orphan template and a template with deployed stacks
      @template_alone      = FactoryGirl.create(:orchestration_template)
      @template_with_stack = FactoryGirl.create(:orchestration_template_with_stacks)
    end

    describe "#in_use?" do
      it "knows whether a template is in use" do
        expect(@template_alone.in_use?).to      be_falsey
        expect(@template_with_stack.in_use?).to be_truthy
      end
    end

    describe ".in_use" do
      it "finds all templates that are in use" do
        inused_templates = OrchestrationTemplate.in_use
        expect(inused_templates.size).to eq(1)
        expect(inused_templates[0]).to eq(@template_with_stack)
      end
    end

    describe ".not_in_use" do
      it "finds all templates that are never deployed" do
        alone_templates = OrchestrationTemplate.not_in_use
        expect(alone_templates.size).to eq(1)
        expect(alone_templates[0]).to eq(@template_alone)
      end
    end
  end

  describe "#eligible_managers" do
    before do
      OrchestrationTemplate.stub(:eligible_manager_types => [ManageIQ::Providers::Amazon::CloudManager, ManageIQ::Providers::Openstack::CloudManager])
      @template = FactoryGirl.create(:orchestration_template)
      @aws = FactoryGirl.create(:ems_amazon)
      @openstack = FactoryGirl.create(:ems_openstack)
    end

    it "lists all eligible managers for a template" do
      expect(@template.eligible_managers).to match_array([@aws, @openstack])
    end
  end

  describe "#validate_content" do
    before do
      @template = FactoryGirl.create(:orchestration_template)
      @manager = FactoryGirl.create(:ems_amazon)
      @manager.stub(:orchestration_template_validate => "Validation Message")
    end

    it "uses caller provided manager to do validation" do
      expect(@template.validate_content(@manager)).to eq("Validation Message")
    end

    it "uses all eligible managers to do validation" do
      @template.stub(:eligible_managers => [@manager])
      expect(@template.validate_content).to eq("Validation Message")
    end

    it "gets an error message if no eligible managers" do
      @template.stub(:eligible_managers => ["Invalid Object"])
      expect(@template.validate_content).to match(/No (.*) is capable to validate the template/)
    end
  end

  describe "#draft=" do
    context "when existing record is not a draft" do
      let(:existing_template) { FactoryGirl.create(:orchestration_template, :draft => false) }

      it "allows duplicated draft record to be added" do
        dup_template = existing_template.dup
        dup_template.update_attributes!(:draft => true)
      end

      it "forbids duplicated final record from being added" do
        dup_template = existing_template.dup
        dup_template.draft = false
        expect { dup_template.save! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "when existing record is a draft" do
      let(:existing_template) { FactoryGirl.create(:orchestration_template, :draft => true) }

      it "allows duplicated draft record to be added" do
        dup_template = existing_template.dup
        dup_template.update_attributes!(:draft => true)
      end

      it "allows duplicated final record to be added" do
        dup_template = existing_template.dup
        dup_template.update_attributes!(:draft => false)
      end
    end
  end

  describe ".find_with_content" do
    it "avoids content comparison but through content hash value comparison" do
      existing_template = FactoryGirl.create(:orchestration_template)
      allow(Digest::MD5).to receive(:hexdigest).and_return(existing_template.md5)

      result = OrchestrationTemplate.find_with_content("#{existing_template.content} content changed")
      expect(result).to eq(existing_template)
    end
  end

  context "when content has non-universal newlines" do
    let(:raw_text) { "abc\r\nxyz\r123\nend" }
    let(:content) { "abc\nxyz\n123\nend\n" }
    let(:existing_template) { FactoryGirl.create(:orchestration_template, :content => raw_text) }

    it "stores content with universal newlines" do
      expect(existing_template.content).to eq(content)
    end

    it "is retrievable through either raw or normalized content" do
      expect(existing_template).to eq(OrchestrationTemplate.find_with_content(raw_text))
      expect(existing_template).to eq(OrchestrationTemplate.find_with_content(content))
    end

    it "does not save a new template if the request has either the raw or normalized content" do
      expect(existing_template).to eq(OrchestrationTemplate.find_or_create_by_contents(:content => raw_text)[0])
      expect(existing_template).to eq(OrchestrationTemplate.find_or_create_by_contents(:content => content)[0])
      expect(OrchestrationTemplate.count).to eq(1)
    end
  end

  describe ".save_with_format_validation!" do
    let(:template) { FactoryGirl.build(:orchestration_template) }

    context "when format validation fails" do
      it "raises an error showing the failure reason" do
        template.stub(:validate_format => "format is invalid")
        expect { template.save_with_format_validation! }
          .to raise_error(MiqException::MiqParsingError, "format is invalid")
      end
    end

    context "when format validation passes" do
      it "saves the template" do
        template.stub(:validate_format => nil)
        expect(template.save_with_format_validation!).to be_truthy
      end
    end

    context "when the template is draft" do
      it "always saves the template" do
        template.draft = true
        template.stub(:validate_format => "format is invalid")
        expect(template.save_with_format_validation!).to be_truthy
      end
    end
  end

  describe ".seed" do
    let(:azure_template) { "azure-single-vm-from-user-image" }

    context "the first time seeding" do
      it "adds templates from default location" do
        OrchestrationTemplate.seed
        expect(OrchestrationTemplate.where(:name => azure_template).count).to eq(1)
      end
    end

    context "when the seeding has been run before" do
      before do
        OrchestrationTemplate.seed
      end

      let(:seeded_template) { OrchestrationTemplate.find_by(:name => azure_template) }

      it "does not add new templates from following runs" do
        OrchestrationTemplate.seed
        expect(OrchestrationTemplate.where(:name => azure_template).count).to eq(1)
      end

      it "does not add new template if the original template has been only renamed" do
        seeded_template.update_attributes(:name => 'other')
        OrchestrationTemplate.seed
        expect(OrchestrationTemplate.where(:name => azure_template).count).to eq(0)
      end

      it "does not add new template if the original template has modified content" do
        seeded_template.update_attributes(:content => '{}')
        OrchestrationTemplate.seed
        expect(OrchestrationTemplate.where(:name => azure_template).count).to eq(1)
      end

      it "adds new template if the original template has been renamed and modified" do
        seeded_template.update_attributes(:name => 'other', :content => '{}')
        OrchestrationTemplate.seed
        expect(OrchestrationTemplate.where(:name => azure_template).count).to eq(1)
      end
    end
  end
end
