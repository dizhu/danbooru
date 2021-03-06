require 'test_helper'

class DmailTest < ActiveSupport::TestCase
  context "A dmail" do
    setup do
      MEMCACHE.flush_all
      @user = FactoryGirl.create(:user)
      CurrentUser.user = @user
      CurrentUser.ip_addr = "127.0.0.1"
      ActionMailer::Base.delivery_method = :test
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.deliveries = []
    end

    teardown do
      CurrentUser.user = nil
    end

    context "filter" do
      setup do
        @recipient = FactoryGirl.create(:user)
        @recipient.create_dmail_filter(:words => "banned")
        @dmail = FactoryGirl.build(:dmail, :title => "xxx", :owner => @recipient, :body => "banned word here", :to => @recipient, :from => @user)
      end

      should "detect banned words" do
        assert(@recipient.dmail_filter.filtered?(@dmail))
      end

      should "autodelete if it has a banned word" do
        @dmail.save
        assert_equal(true, @dmail.is_deleted?)
        assert_equal(true, @dmail.is_read?)
      end

      should "not update the recipient's has_mail if filtered" do
        @dmail.save
        @recipient.reload
        assert_equal(false, @recipient.has_mail?)
      end

      context "that is empty" do
        setup do
          @recipient.dmail_filter.update_attributes(:words => "   ")
        end

        should "not filter everything" do
          assert(!@recipient.dmail_filter.filtered?(@dmail))
        end
      end
    end

    context "from a banned user" do
      setup do
        @user.update_attribute(:is_banned, true)
      end

      should "not validate" do
        dmail = FactoryGirl.build(:dmail, :title => "xxx", :owner => @user)
        dmail.save
        assert_equal(1, dmail.errors.size)
        assert_equal(["Sender is banned and cannot send messages"], dmail.errors.full_messages)
      end
    end

    context "search" do
      should "return results based on title contents" do
        dmail = FactoryGirl.create(:dmail, :title => "xxx", :owner => @user)
        matches = Dmail.search_message("xxx")
        assert(matches.any?)
        matches = Dmail.search_message("aaa")
        assert(matches.empty?)
      end

      should "return results based on body contents" do
        dmail = FactoryGirl.create(:dmail, :body => "xxx", :owner => @user)
        matches = Dmail.search_message("xxx")
        assert(matches.any?)
        matches = Dmail.search_message("aaa")
        assert(matches.empty?)
      end
    end

    should "should parse user names" do
      dmail = FactoryGirl.build(:dmail, :owner => @user)
      dmail.to_id = nil
      dmail.to_name = @user.name
      assert(dmail.to_id == @user.id)
    end

    should "construct a response" do
      dmail = FactoryGirl.create(:dmail, :owner => @user)
      response = dmail.build_response
      assert_equal("Re: #{dmail.title}", response.title)
      assert_equal(dmail.from_id, response.to_id)
      assert_equal(dmail.to_id, response.from_id)
    end

    should "create a copy for each user" do
      @new_user = FactoryGirl.create(:user)
      assert_difference("Dmail.count", 2) do
        Dmail.create_split(:to_id => @new_user.id, :title => "foo", :body => "foo")
      end
    end

    should "send an email if the user wants it" do
      user = FactoryGirl.create(:user, :receive_email_notifications => true)
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        FactoryGirl.create(:dmail, :to => user, :owner => user)
      end
    end

    should "create only one message for a split response" do
      user = FactoryGirl.create(:user, :receive_email_notifications => true)
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        Dmail.create_split(:to_id => user.id, :title => "foo", :body => "foo")
      end
    end

    should "be marked as read after the user reads it" do
      dmail = FactoryGirl.create(:dmail, :owner => @user)
      assert(!dmail.is_read?)
      dmail.mark_as_read!
      assert(dmail.is_read?)
    end

    should "notify the recipient he has mail" do
      @recipient = FactoryGirl.create(:user)
      dmail = FactoryGirl.create(:dmail, :owner => @recipient)
      recipient = dmail.to
      recipient.reload
      assert(recipient.has_mail?)

      CurrentUser.scoped(recipient) do
        dmail.mark_as_read!
      end

      recipient.reload
      assert(!recipient.has_mail?)
    end
  end
end
