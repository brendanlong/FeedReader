const string host_env = "FEEDBIN_TEST_HOST";
const string user_env = "FEEDBIN_TEST_USER";
const string password_env = "FEEDBIN_TEST_PASSWORD";

void delete_subscription(FeedbinAPI api, string url)
{
    var subscriptions = api.get_subscriptions().wait();
    foreach(var subscription in subscriptions)
    {
        if(subscription.feed_url != url)
            continue;
        api.delete_subscription(subscription.id);
        break;
    }
}

void add_login_tests(string host)
{
    string? username = Environment.get_variable(user_env);
    string? password = Environment.get_variable(password_env);
    if(username == null || password == null)
		return;

	// Stick a random number at the end of Feed URL's to ensure that they're
	// unique, even if we run two tests against the same account
	uint nonce = Random.next_int();

    Test.add_data_func ("/feedbinapi/login", () => {

        var api = new FeedbinAPI(username, password, null, host);
        assert(api.login().wait());

        api = new FeedbinAPI("wrong", "password", null, host);
        assert(!api.login().wait());

        api.username = username;
        assert(!api.login().wait());

        api.password = password;
        assert(api.login().wait());
    });

    Test.add_data_func ("/feedbinapi/subscription", () => {
        if(username == null || password == null)
        {
            Test.skip(@"Need $user_env and $password_env set to run Feedbin tests");
            return;
        }

        var api = new FeedbinAPI(username, password, null, host);

        var url = "https://www.brendanlong.com/feeds/all.atom.xml?feedreader-test-subscribe-$nonce";
        delete_subscription(api, url);

        var subscription = api.add_subscription(url).wait();
        assert(subscription.id != 0);

		{
			var got_subscription = api.get_subscription(subscription.id).wait();
			assert(got_subscription.id == subscription.id);
		}

        bool found_subscription = false;
        foreach(var got_subscription in api.get_subscriptions().wait())
        {
            if(got_subscription.id == subscription.id)
            {
				assert(got_subscription.feed_id == subscription.feed_id);
				assert(got_subscription.feed_url == subscription.feed_url);
				assert(got_subscription.site_url == subscription.site_url);
				assert(got_subscription.title == subscription.title);
                found_subscription = true;
            }
        }
        assert(found_subscription);

        string title = "Rename test";
        api.rename_subscription(subscription.id, title).wait();
        var renamed_subscription = api.get_subscription(subscription.id).wait();
        assert(renamed_subscription.title == title);

        api.delete_subscription(subscription.id).wait();
        foreach(var got_subscription in api.get_subscriptions().wait())
        {
            assert(got_subscription.id != subscription.id);
            assert(got_subscription.feed_url != url);
        }
    });

    Test.add_data_func ("/feedbinapi/taggings", () => {
        if(username == null || password == null)
        {
            Test.skip(@"Need $user_env and $password_env set to run Feedbin tests");
            return;
        }

        var api = new FeedbinAPI(username, password, null, host);

        var url = @"https://www.brendanlong.com/feeds/all.atom.xml?feedreader-test-taggings-$nonce";
        delete_subscription(api, url);

        var subscription = api.add_subscription(url).wait();

        // The subscription is new so it shouldn't have any taggings
        var taggings = api.get_taggings().wait();
        foreach(var tagging in taggings)
        {
            assert(tagging.feed_id != subscription.feed_id);
        }

        string category = "Taggings Test";
        api.add_tagging(subscription.feed_id, category).wait();

        // Check taggings
        int64? tagging_id = null;
        foreach(var tagging in api.get_taggings().wait())
        {
            if(tagging.feed_id == subscription.feed_id)
            {
                assert(tagging.name == category);
                tagging_id = tagging.id;
                break;
            }
        }
        assert(tagging_id != null);

        // Delete the tag and verify that it's gone
        api.delete_tagging(tagging_id).wait();
        foreach(var tagging in api.get_taggings().wait())
        {
            assert(tagging.feed_id != subscription.feed_id);
		}

		// cleanup
		api.delete_subscription(subscription.id).wait();
    });

    Test.add_data_func ("/feedbinapi/entries", () => {
        if(username == null || password == null)
        {
            Test.skip(@"Need $user_env and $password_env set to run Feedbin tests");
            return;
        }

        var api = new FeedbinAPI(username, password, null, host);

		// Note: This one shouldn't be deleted or recreated, since we want the entries to be available
        var url = "https://www.brendanlong.com/feeds/all.atom.xml?feed-reader-test-entries";

        var subscription = api.add_subscription(url).wait();

        /* FIXME: Figure out why this next line is failing
        var entries = api.get_entries(1, false, null, subscription.feed_id);
        foreach(var entry in entries)
        {
            assert(entry.feed_id == subscription.feed_id);
        }

		assert(entries.size > 0);
		int i = Random.int_range(0, entries.size);
        var entry = entries.to_array()[i];
        var entry_ids = new Gee.ArrayList<int64?>();
        entry_ids.add(entry.id);

        // read status
        api.set_entries_read(entry_ids, true);
        var unread_entries = api.get_unread_entries();
        assert(!unread_entries.contains(entry.id));

        api.set_entries_read(entry_ids, false);
        unread_entries = api.get_unread_entries();
        assert(unread_entries.contains(entry.id));

        api.set_entries_read(entry_ids, true);
        unread_entries = api.get_unread_entries();
        assert(!unread_entries.contains(entry.id));

        // starred status
        api.set_entries_starred(entry_ids, true);
        var starred_entries = api.get_starred_entries();
        assert(starred_entries.contains(entry.id));

        api.set_entries_starred(entry_ids, false);
        starred_entries = api.get_starred_entries();
        assert(!starred_entries.contains(entry.id));

        api.set_entries_starred(entry_ids, true);
        starred_entries = api.get_starred_entries();
        assert(starred_entries.contains(entry.id));
        */
    });

    Test.add_data_func ("/feedbinapi/favicons", () => {
        if(username == null || password == null)
        {
            Test.skip(@"Need $user_env and $password_env set to run Feedbin tests");
            return;
		}

		Bytes? expected_favicon;
		{
			var session = new Soup.Session();
			var message = new Soup.Message("GET", "https://www.brendanlong.com/theme/favicon.ico");
			var inputstream = session.send(message);
			var bytearray = new ByteArray();
			uint8[] buffer = new uint8[4096];
			size_t bytes_read = 0;
			do
			{
				inputstream.read_all(buffer, out bytes_read);
				bytearray.append(buffer[0:bytes_read]);
			}
			while(bytes_read == 4096);
			expected_favicon = ByteArray.free_to_bytes(bytearray);
		}

        var api = new FeedbinAPI(username, password, null, host);

		// Note: This one shouldn't be deleted or recreated, since we want the entries to be available
        var url = "https://www.brendanlong.com/feeds/all.atom.xml?feed-reader-test-favicons";

		var subscription = api.add_subscription(url).wait();
		var favicons = api.get_favicons().wait();
		bool found_favicon = false;
		foreach(var i in favicons.entries)
		{
			if(i.key != "www.brendanlong.com")
				continue;
			assert(i.value == expected_favicon);
			found_favicon = true;
			break;
		}
		// FIXME: We don't download icons on the test server because favicon downloading
		// is handled by a different service
		//assert(found_favicon);
	});
}

void main(string[] args)
{
	Test.init(ref args);

	string? host = Environment.get_variable(host_env);
	if(host == null)
		host = "https://api.feedbin.com";

    // Tests that don't need a login
    Test.add_data_func ("/feedbinapi/construct", () => {
        var api = new FeedbinAPI("user", "password", null, host);
        assert(api != null);
    });

    Test.add_data_func ("/feedbinapi/bad login", () => {
        var api = new FeedbinAPI("user", "password", null, host);

        assert(!api.login().wait());
    });

    add_login_tests(host);

    Test.run ();
}
