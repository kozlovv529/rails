# frozen_string_literal: true

require "cases/helper"
require "models/person"
require "action_dispatch"

module ActiveRecord
  class DatabaseSelectorTest < ActiveRecord::TestCase
    setup do
      @session_store = {}
      @session = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session.new(@session_store)
    end

    def test_empty_session
      assert_equal Time.at(0), @session.last_write_timestamp
    end

    def test_writing_the_session_timestamps
      assert @session.update_last_write_timestamp

      session2 = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session.new(@session_store)
      assert_equal @session.last_write_timestamp, session2.last_write_timestamp
    end

    def test_writing_session_time_changes
      assert @session.update_last_write_timestamp

      before = @session.last_write_timestamp
      sleep(0.1)

      assert @session.update_last_write_timestamp
      assert_not_equal before, @session.last_write_timestamp
    end

    def test_read_from_replicas
      @session_store[:last_write] = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session.convert_time_to_timestamp(Time.now - 5.seconds)

      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session)

      called = false
      resolver.read do
        called = true
        assert ActiveRecord::Base.connected_to?(role: :reading)
      end
      assert called
    end

    def test_read_from_primary
      @session_store[:last_write] = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session.convert_time_to_timestamp(Time.now)

      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session)

      called = false
      resolver.read do
        called = true
        assert ActiveRecord::Base.connected_to?(role: :writing)
      end
      assert called
    end

    def test_write_to_primary
      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session)

      # Session should start empty
      assert_nil @session_store[:last_write]

      called = false
      resolver.write do
        assert ActiveRecord::Base.connected_to?(role: :writing)
        called = true
      end
      assert called

      # and be populated by the last write time
      assert @session_store[:last_write]
    end

    def test_write_to_primary_with_exception
      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session)

      # Session should start empty
      assert_nil @session_store[:last_write]

      called = false
      assert_raises(ActiveRecord::RecordNotFound) do
        resolver.write do
          assert ActiveRecord::Base.connected_to?(role: :writing)
          called = true
          raise ActiveRecord::RecordNotFound
        end
      end
      assert called

      # and be populated by the last write time
      assert @session_store[:last_write]
    end

    def test_read_from_primary_with_options
      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session, delay: 5.seconds)

      # Session should start empty
      assert_nil @session_store[:last_write]

      called = false
      resolver.write do
        assert ActiveRecord::Base.connected_to?(role: :writing)
        called = true
      end
      assert called

      # and be populated by the last write time
      assert @session_store[:last_write]

      read = false
      resolver.read do
        assert ActiveRecord::Base.connected_to?(role: :writing)
        read = true
      end
      assert read
    end

    def test_read_from_replica_with_no_delay
      resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver.new(@session, delay: 0.seconds)

      # Session should start empty
      assert_nil @session_store[:last_write]

      called = false
      resolver.write do
        assert ActiveRecord::Base.connected_to?(role: :writing)
        called = true
      end
      assert called

      # and be populated by the last write time
      assert @session_store[:last_write]

      read = false
      resolver.read do
        assert ActiveRecord::Base.connected_to?(role: :reading)
        read = true
      end
      assert read
    end

    def test_the_middleware_chooses_writing_role_with_POST_request
      middleware = ActiveRecord::Middleware::DatabaseSelector.new(lambda { |env|
        assert ActiveRecord::Base.connected_to?(role: :writing)
        [200, {}, ["body"]]
      })
      assert_equal [200, {}, ["body"]], middleware.call("REQUEST_METHOD" => "POST")
    end

    def test_the_middleware_chooses_reading_role_with_GET_request
      middleware = ActiveRecord::Middleware::DatabaseSelector.new(lambda { |env|
        assert ActiveRecord::Base.connected_to?(role: :reading)
        [200, {}, ["body"]]
      })
      assert_equal [200, {}, ["body"]], middleware.call("REQUEST_METHOD" => "GET")
    end
  end
end
