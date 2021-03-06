import vibe.d;
import std.string : indexOf, replace;
import std.conv : to;
import std.json;
import std.file;
import std.datetime;
import std.path : baseName;

shared static this()
{ 
	auto router = new UrlRouter;
	router	.get("/", &index)
		.get("/show/:next", &show)
		.get("/*", serveStaticFiles("public"));
	
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	settings.errorPageHandler = toDelegate(&errorPage);
	
	listenHttp(settings, router);
}

void errorPage(HttpServerRequest req, HttpServerResponse resp, HttpServerErrorInfo e)
{
	if(e.code == 404)
	{
		resp.renderCompat!(
			"errors/404.dt",
			HttpServerRequest, "req",
			HttpServerResponse, "resp"
		)(req, resp);
	}
	else
	{
		resp.renderCompat!(
			"errors/error.dt",
			int, "code",
			string, "message"
		)(e.code, e.message);
	}
}

void index(HttpServerRequest req, HttpServerResponse resp)
{
	resp.redirect("/show/1");
}

void show(HttpServerRequest req, HttpServerResponse resp)
{
	string url = "http://www.reddit.com/r/funny.json";
	string local = "cache/funny.json";

	if("next" in req.params)
	{
		if(req.params["next"] != "1")
		{
			url ~= "?after=" ~ req.params["next"] ~ "&count=25";
			local = "cache/funny.json_" ~ req.params["next"];
		}
	}
	
	auto cache = CacheMan(url, 10, local);
	JSONValue[string] entries = parseJSON(cache.getContents()).object;
	Entry[] data;
	string last = entries["data"]["after"].str;
	
	foreach(entry; entries["data"]["children"].array)
	{
		Entry current;
		current.original = entry["data"]["url"].str;
		current.url = getDirectLink(entry["data"]["url"].str);
		current.title = entry["data"]["title"].str;
		current.score = to!string(entry["data"]["score"].uinteger);
		current.author = entry["data"]["author"].str;
		current.created_at = to!string(entry["data"]["created"].floating);
		current.permalink = "http://www.reddit.com" ~ entry["data"]["permalink"].str;
		data ~= current;
	}
	
	resp.renderCompat!(
		"index.dt", 
		HttpServerRequest, "req",
		HttpServerResponse, "resp",
		Entry[], "data",
		string, "last"
	)(req, resp, data, last);
}

struct Entry
{
	string original;
	string url; /* actual URL of the image */
	string title;
	string score;
	string author;
	string permalink; /* comments page on reddit */
	string created_at;
}

struct CacheMan
{
	string remote;
	string local;
	int lifetime;
	
	this(string url, int lifetime, string file = "")
	{
		remote = url;
		local = file == "" ? baseName(url) : file;
		this.lifetime = lifetime;
	}
	
	string getContents()
	{
		if(!stillFresh())
		{
			download(remote, local);
		}
		
		return readText(local);
	}
	
	private bool stillFresh()
	{
		if(!exists(local))
		{
			return false;
		}
		
		return timeLastModified(local) + dur!"minutes"(lifetime) > Clock.currTime();
	}
}

string getDirectLink(string imgUrl)
{
	if(imgUrl.indexOf("imgur") == -1)
	{
		return imgUrl;
	}
	else if(imgUrl.indexOf("/a/") != -1)
	{
		/* in case of album */
		return imgUrl;
	}
	
	foreach(ext; ["jpg", "png", "gif", "jpeg"])
	{
		if(imgUrl.endsWith(ext))
		{
			/* so as not to get huge images */
			return imgUrl.replace("." ~ ext, "l." ~ ext);	
		}
	}
	
	return imgUrl ~ "l.png";
}

unittest
{
	assert(getLink("http://imgur.com/img.png") == "http://imgur.com/img.png");
	assert(getLink("http://imgur.com/img") == "http://imgur.com/img.png");
	assert(getLink("http://imgur.com/a/kjdlKd") == "http://imgur.com/a/kjdlKd");
	assert(getLink("http://image.com/show.php?id=3832") == "http://image.com/show.php?id=3832");
}
