//	This file is part of FeedReader.
//
//	FeedReader is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	FeedReader is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with FeedReader.  If not, see <http://www.gnu.org/licenses/>.

using Gee;

// TODO: Make a general-purpose HttpClient module with these errors
public errordomain FeedbinError {
	INVALID_FORMAT,
	MULTIPLE_CHOICES,
	NO_CONNECTION,
	NOT_AUTHORIZED,
	NOT_FOUND,
	UNKNOWN_ERROR
}

public class FeedbinAPI : Object {
	private const string BASE_URI_FORMAT = "%s/v2/";

	private Soup.Session m_session;
	private string m_base_uri;
	public string username { get ; set; }
	public string password { get ; set; }

	public FeedbinAPI(string username, string password, string? user_agent = null, string? host = "https://api.feedbin.com")
	{
		this.username = username;
		this.password = password;
		m_base_uri = BASE_URI_FORMAT.printf(host);
		m_session = new Soup.Session();
		m_session.use_thread_context = true;

		if(user_agent != null)
			m_session.user_agent = user_agent;

		m_session.authenticate.connect(authenticate);
	}

	~FeedbinAPI()
	{
		m_session.authenticate.disconnect(authenticate);
	}

	private void authenticate(Soup.Message msg, Soup.Auth auth, bool retrying)
	{
		if(!retrying)
			auth.authenticate(this.username, this.password);
	}

	private Future<Soup.Message> request(string method, string path, string? input = null, Cancellable? cancellable = null)
	{
		var message = new Soup.Message(method, m_base_uri + path);

		if(method == "POST" || method == "PUT")
			message.request_headers.append("Content-Type", "application/json; charset=utf-8");

		if(input != null)
			message.request_body.append_take(input.data);

		var promise = new Promise<Soup.Message>();
		var thread = new Thread<void*>(null, () => {
			var context = new MainContext();
			context.push_thread_default();
			assert(context.is_owner());
			context.release();
			assert(!context.is_owner());

			m_session.send_message(message);
			var status = message.status_code;
			if(status < 200 || status >= 400)
			{
				FeedbinError e;
				switch(status)
				{
				case Soup.Status.CANT_RESOLVE:
				case Soup.Status.CANT_RESOLVE_PROXY:
				case Soup.Status.CANT_CONNECT:
				case Soup.Status.CANT_CONNECT_PROXY:
					e = new FeedbinError.NO_CONNECTION(@"Connection to $m_base_uri failed");
					break;
				case Soup.Status.UNAUTHORIZED:
					e = new FeedbinError.NOT_AUTHORIZED(@"Not authorized to $method $path");
					break;
				case Soup.Status.NOT_FOUND:
					e = new FeedbinError.NOT_FOUND(@"$method $path not found");
					break;
				default:
					string phrase = Soup.Status.get_phrase(status);
					e = new FeedbinError.UNKNOWN_ERROR(@"Unexpected status $status ($phrase) for $method $path");
					break;
				}
				promise.set_exception(e);
			}
			else
			{
				promise.set_value(message);
			}
			context.pop_thread_default();
			return null;
		});
		return promise.future;
	}

	// TODO: Move to DateUtils
	private static DateTime string_to_datetime(string s) throws FeedbinError
	{
		var time = TimeVal();
		if(!time.from_iso8601(s))
			throw new FeedbinError.INVALID_FORMAT(@"Expected date but got $s");
		return new DateTime.from_timeval_utc(time);
	}

	// TODO: JSON utils?
	private static DateTime get_datetime_member(Json.Object obj, string name) throws FeedbinError
	{
		var s = obj.get_string_member(name);
		return string_to_datetime(s);
	}

	private Future<Soup.Message> post_request(string path, string input, Cancellable? cancellable = null)
	{
		return request("POST", path, input, cancellable);
	}

	private Future<Soup.Message> delete_request(string path, string? input = null, Cancellable? cancellable = null)
	{
		return request("DELETE", path, input, cancellable);
	}

	private Future<Soup.Message> get_request(string path, Cancellable? cancellable = null)
	{
		return request("GET", path, null, cancellable);
	}

	private static Json.Node parse_json(Soup.Message response) throws FeedbinError
	{
		var method = response.method;
		var uri = response.uri.to_string(false);
		string content = (string)response.response_body.flatten().data;
		if(content == null)
		{
			throw new FeedbinError.INVALID_FORMAT(@"$method $uri returned no content but expected JSON");
		}

		var parser = new Json.Parser();
		try
		{
			parser.load_from_data(content, -1);
		}
		catch (Error e)
		{
			throw new FeedbinError.INVALID_FORMAT(@"$method $uri returned invalid JSON: " + e.message + "\nContent is: $content");
		}
		return parser.get_root();
	}

	private Future<Json.Node> get_json(string path, Cancellable? cancellable = null)
	{
		return get_request(path, cancellable)
			.map((Future.MapFunc<Json.Node, Soup.Message>)parse_json);
	}

	private Future<Soup.Message> post_json_object(string path, Json.Object obj)
	{
		var root = new Json.Node(Json.NodeType.OBJECT);
		root.set_object(obj);

		var gen = new Json.Generator();
		gen.set_root(root);
		var data = gen.to_data(null);

		return post_request(path, data);
	}

	[CCode (has_target = false)]
	private delegate O MapExceptionFunc<O>(Error e) throws Error;

	private static Future<T> map_error<T>(Future<T> input, MapExceptionFunc<T> func)
	{
		var output = new Promise<T>();
		input.wait_async.begin((obj, res) => {
			try
			{
				try
				{
					output.set_value(input.wait_async.end(res));
				}
				catch(FutureError.EXCEPTION e)
				{
					output.set_value(func(e));
				}
			}
			catch(Error e)
			{
				output.set_exception(e);
			}
		});
		return output.future;
	}

	public Future<bool> login()
	{
		var f1 = get_request("authentication.json");
		var f2 = f1.map<bool>(response => {
			return response.status_code == Soup.Status.OK;
		});
		return map_error<bool>(f2, (e) => {
			try
			{
				throw e;
			}
			catch(FeedbinError.NOT_AUTHORIZED e)
			{
				return false;
			}
		});
	}

	public struct Subscription {
		int64 id;
		DateTime created_at;
		int64 feed_id;
		string? title;
		string? feed_url;
		string? site_url;

		public Subscription.from_json(Json.Object object) throws FeedbinError
		{
			id = object.get_int_member("id");
			created_at = get_datetime_member(object, "created_at");
			feed_id = object.get_int_member("feed_id");
			title = object.get_string_member("title");
			feed_url = object.get_string_member("feed_url");
			site_url = object.get_string_member("site_url");
		}
	}

	public Future<Subscription?> get_subscription(int64 subscription_id)
	{
		var f1 = get_json(@"subscriptions/$subscription_id.json");
		return f1.map<Subscription?>(root => {
			return Subscription.from_json(root.get_object());
		});
	}

	public Future<Gee.List<Subscription?>> get_subscriptions()
	{
		var f1 = get_json("subscriptions.json");
		return f1.map<Gee.List<Subscription?>>(root => {
			var subscriptions = new Gee.ArrayList<Subscription?>();
			var array = root.get_array();
			for(var i = 0; i < array.get_length(); ++i)
			{
				var node = array.get_object_element(i);
				subscriptions.add(Subscription.from_json(node));
			}
			return subscriptions;
		});
	}

	public Future<bool> delete_subscription(int64 subscription_id)
	{
		var f1 = delete_request(@"subscriptions/$subscription_id.json");
		return f1.map<bool>(response => true);
	}

	public Future<Subscription?> add_subscription(string url)
	{
		Json.Object object = new Json.Object();
		object.set_string_member("feed_url", url);

		var f1 = post_json_object("subscriptions.json", object);
		return f1.map<Subscription?>(response => {
			if(response.status_code == 300)
				throw new FeedbinError.MULTIPLE_CHOICES("Site $url has multiple feeds to subscribe to");

			var root = parse_json(response);
			return Subscription.from_json(root.get_object());
		});
	}

	public Future<bool> rename_subscription(int64 subscription_id, string title)
	{
		Json.Object object = new Json.Object();
		object.set_string_member("title", title);
		var f1 = post_json_object(@"subscriptions/$subscription_id/update.json", object);
		return f1.map<bool>(response => { return true; });
	}

	public struct Tagging
	{
		int64 id;
		int64 feed_id;
		string name;

		public Tagging.from_json(Json.Object object)
		{
			id = object.get_int_member("id");
			feed_id = object.get_int_member("feed_id");
			name = object.get_string_member("name");
		}
	}

	public Future<bool> add_tagging(int64 feed_id, string tag_name)
	{
		Json.Object object = new Json.Object();
		object.set_int_member("feed_id", feed_id);
		object.set_string_member("name", tag_name);

		var f1 = post_json_object("taggings.json", object);
		// TODO: Return id
		return f1.map<bool>(res => { return true; });
	}

	public Future<bool> delete_tagging(int64 tagging_id)
	{
		var f1 = delete_request(@"taggings/$tagging_id.json");
		return f1.map<bool>(res => { return true; });
	}

	public Future<Gee.List<Tagging?>> get_taggings()
	{
		var f1 = get_json("taggings.json");
		return f1.map<Gee.List<Tagging?>>(root => {
			var taggings = new Gee.ArrayList<Tagging?>();
			var array = root.get_array();
			for(var i = 0; i < array.get_length(); ++i)
			{
				var object = array.get_object_element(i);
				taggings.add(Tagging.from_json(object));
			}
			return taggings;
		});
	}

	public struct Entry
	{
		int64 id;
		int64 feed_id;
		string? title;
		string? url;
		string? author;
		string? content;
		string? summary;
		DateTime published;
		DateTime created_at;

		public Entry.from_json(Json.Object object)
		{
			id = object.get_int_member("id");
			feed_id = object.get_int_member("feed_id");
			title = object.get_string_member("title");
			url = object.get_string_member("url");
			author = object.get_string_member("author");
			content = object.get_string_member("content");
			summary = object.get_string_member("summary");
			published = get_datetime_member(object, "published");
			created_at = get_datetime_member(object, "created_at");
		}
	}

	public Future<Gee.List<Entry?>> get_entries(int page, bool only_starred, DateTime? since, int64? feed_id = null)
	{
		string starred = only_starred ? "true" : "false";
		string path = @"entries.json?per_page=100&page=$page&starred=$starred&include_enclosure=true";
		if(since != null)
		{
			var t = GLib.TimeVal();
			if(since.to_timeval(out t))
			{
				path += "&since=" + t.to_iso8601();
			}
		}

		if(feed_id != null)
			path = @"feeds/$feed_id/$path";

		var f1 = get_json(path);
		var f2 = f1.map<Gee.List<Entry?>>(root => {
			var entries = new Gee.ArrayList<Entry?>();
			var array = root.get_array();
			for(var i = 0; i < array.get_length(); ++i)
			{
				var object = array.get_object_element(i);
				entries.add(Entry.from_json(object));
			}
			return entries;
		});
		return map_error<Gee.List<Entry?>>(f2, e => {
			try
			{
				throw e;
			}
			catch(FeedbinError.NOT_FOUND e)
			{
				return Gee.List.empty<Entry?>();
			}
		});
	}

	private Future<Gee.Set<int64?>> get_x_entries(string path)
	{
		var f1 = get_json(path);
		return f1.map<Gee.Set<int64?>>(root => {
			var array = root.get_array();
			// We have to set the hash function here manually or contains() won't
			// work right -- presumably because it's trying to do pointer comparisons?
			var ids = new Gee.HashSet<int64?>(
				(n) => { return int64_hash(n); },
				(a, b) => { return int64_equal(a, b); });
			for(var i = 0; i < array.get_length(); ++i)
			{
				ids.add(array.get_int_element(i));
			}
			return ids;
		});
	}

	public Future<Gee.Set<int64?>> get_unread_entries()
	{
		return get_x_entries("unread_entries.json");
	}

	public Future<Gee.Set<int64?>> get_starred_entries()
	{
		return get_x_entries("starred_entries.json");
	}

	private Future<bool> set_entries_status(string type, Gee.Collection<int64?> entry_ids, bool create)
	{
		Json.Array array = new Json.Array();
		foreach(var id in entry_ids)
		{
			array.add_int_element(id);
		}

		Json.Object object = new Json.Object();
		object.set_array_member(type, array);

		string path = create ? @"$type.json" : @"$type/delete.json";
		var f1 = post_json_object(path, object);
		return f1.map<bool>(response => { return true; });
	}

	public Future<bool> set_entries_read(Gee.Collection<int64?> entry_ids, bool read)
	{
		return set_entries_status("unread_entries", entry_ids, !read);
	}

	public Future<bool> set_entries_starred(Gee.Collection<int64?> entry_ids, bool starred)
	{
		return set_entries_status("starred_entries", entry_ids, starred);
	}

	public Future<Gee.Map<string, Bytes?>> get_favicons()
	{
		// The favicon API isn't public right now; make sure to handle it
		// suddenly changing or disappearing
		var f1 = get_json("favicons.json");
		var f2 = f1.map<Gee.Map<string, Bytes?>>(root => {
			if(root == null)
				return Gee.Map.empty<string, Bytes?>();

			var array = root.get_array();
			if(array == null)
				return Gee.Map.empty<string, Bytes?>();

			var favicons = new Gee.HashMap<string, Bytes?>();
			for(var i = 0; i < array.get_length(); ++i)
			{
				var obj = array.get_object_element(i);
				string host = obj.get_string_member("host");
				if(host == null)
					continue;
				var favicon_encoded = obj.get_string_member("favicon");
				if(favicon_encoded == null)
					continue;
				var favicon = new Bytes.take(Base64.decode(favicon_encoded));
				favicons.set(host, favicon);
			}
			return favicons;
		});
		return map_error<Gee.Map<string, Bytes?>>(f2, e => {
			return Gee.Map.empty<string, Bytes?>();
		});
	}
}
