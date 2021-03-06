module upyun.d;

private {
import std.algorithm: startsWith;
import std.array: join;
import std.datetime;
import std.digest.md;
import std.file: read, write, exists;
import std.string: format, split;
import vibe.data.json;
import vibe.http.client;
import vibe.http.form;
import vibe.stream.operations;
}

/// UpYun Endpoints
public enum Endpoint {
    /// Auto select
    auto_ = 0,
    /// China Telecom
    telecom,
    /// China Unicom(China Netcom)
    cnc,
    /// China Tietong(China Mobile)
    ctt
}

/// UpYun function return value
public struct Ret {
    /// HTTP status code
    int statusCode;
    /// Error code
    int errorCode;
    /// Error message
    string errorMsg;
}

/// UpYun upload result headers
public struct UploadRes {
    int width;
    int height;
    int frames;
    string fileType;
}

/// Gmkerl types
public enum GmkerlType {
    ignore,
    fixWidth,
    fixHeight,
    fixWidthOrHeight,
    fixBoth,
    fixMax,
    fixMin,
    fixScale,
}

/// Gmkerl on/off switch
public enum GmkerlSwitch {
    ignore,
    on,
    off,
}

/// Gmkerl rotate types
public enum GmkerlRotate {
    ignore,
    rauto,
    r90,
    r180,
    r270,
}

public struct Gmkerl {
    /// image process type
    GmkerlType type = GmkerlType.ignore;
    /// MMxNN for fixBoth or fixWidthOrHeight, otherwise a simple number, ignored when type is ignore
    string value = null;
    /// image quality(1-100), ignored if set to 0
    int quality = 0;
    /// unsharp image
    GmkerlSwitch unsharp = GmkerlSwitch.ignore;
    /// image thumbnail params, set in control pannel, ignored if set to null
    string thumbnail = null;
    /// exif switch
    GmkerlSwitch exifSwitch = GmkerlSwitch.ignore;
    /// x,y,width,height like 0,0,100,200, ignored if set to null
    string crop = null;
    /// auto / 90 / 180 / 270
    GmkerlRotate rotate = GmkerlRotate.ignore;
    /// watermark text, ignored if set to null
    string watermarkText = null;
    /** watermark font, ignored and defaults to simsun if set to null
     *  available fonts for Chinese: simsun, simhei, simkai, simli, simyou, simfang
     */
    string watermarkFont = null;
    /// watermark size, ignored and defaults to 32 if set to 0
    int watermarkSize = 0;
    /** watermark alignment, the format is valign,halign, ignore if set to null;
     *  available params for valign: top, middle, bottom
     *  available params for halign: left, center, right
     */
    string watermarkAlign = null;
    /// watermark margin, x,y, ignored if set to null
    string watermarkMargin = null;
    /// watermark opacity, ignored if set to -1
    int watermarkOpacity = -1;
    /// watermark color in RGB format #RRGGBB, ignored and defaults to #000000 if set to null
    string watermarkColor = null;
    /// watermark border color in RGB format, ignored and defaults to no border if set to null
    string watermarkBorder = null;
}

/// UpYun config
public struct UpYunConfig {
    /// Username
    string user;
    /// Password
    string passwd;
    /// Bucket path, begins with '/'
    string bucket;
    /// Using https:// instead of http://
    bool useHttps = false;
    // Print some debug information
    bool debugOutput = false;
    // Network endpoint
    Endpoint endpoint;
};

/// UpYun file info used in listDir
public struct FileInfo {
    /// File name
    string filename;
    /// Is folder or not
    bool isFolder;
    /// File size in bytes
    ulong size;
    /// Unix timestamp
    ulong timestamp;
}


/// Directory list iterator
public struct DirIterator {
    /// count limit of each request
    int limit = 100;
    /// false/true for file time ascend/descend
    bool order = false;

    private string listIter;
}

/// UpYun main class
public class UpYun {
private:
    static string[] api_url_ = [
        "v0.api.upyun.com",
        "v1.api.upyun.com",
        "v2.api.upyun.com",
        "v3.api.upyun.com"
    ];
    static string purge_url_ = "http://purge.upyun.com/purge/";

    UpYunConfig config_;
    string passhash_;

    struct RetInternal {
        Ret ret;
        string[string] response;
        ubyte[] bodyRaw;
    }

public:
    /// Create UpYun object with certain config
    this(ref UpYunConfig config) {
        config_ = config;
        passhash_ = toHexString!(LetterCase.lower, Order.increasing)(md5Of(config_.passwd)).dup;
    }

    /**
     * Upload a file
     *
     * Params:
     *   res         = receive some params in response headers
     *   path        = remote path
     *   localFile   = local file path
     *   gmkerl      = Gmkerl data
     *   md5Verify   = emit md5 field to verify file after uploading finished
     *   contentType = overwrite auto detected 'Content-Type' for the file
     *   secret      = secret key for visiting
     */
    Ret uploadFile(ref UploadRes res, string path, string localFile, Gmkerl* gmkerl = null, bool md5Verify = false, string contentType = null, string secret = null) {
        if(!exists(localFile)) {
            return Ret(-1, -1, "File not found!");
        }
        return uploadFile(res, path, cast(ubyte[])read(localFile), gmkerl, md5Verify, contentType, secret);
    }

    /**
     * Upload a file
     *
     * Params:
     *   res         = receive some params in response headers
     *   path        = remote path
     *   data        = file content
     *   gmkerl      = Gmkerl data
     *   md5Verify   = emit md5 field to verify file after uploading finished
     *   contentType = overwrite auto detected 'Content-Type' for the file
     *   secret      = secret key for visiting
     */
    Ret uploadFile(ref UploadRes res, string path, ubyte[] data, Gmkerl* gmkerl = null, bool md5Verify = false, string contentType = null, string secret = null) {
        string[string] headers;
        if (gmkerl !is null) {
            switch(gmkerl.type) {
                case GmkerlType.fixWidth:
                    headers["x-gmkerl-type"] = "fix_width"; break;
                case GmkerlType.fixHeight:
                    headers["x-gmkerl-type"] = "fix_height"; break;
                case GmkerlType.fixWidthOrHeight:
                    headers["x-gmkerl-type"] = "fix_width_or_height"; break;
                case GmkerlType.fixBoth:
                    headers["x-gmkerl-type"] = "fix_both"; break;
                case GmkerlType.fixMax:
                    headers["x-gmkerl-type"] = "fix_max"; break;
                case GmkerlType.fixMin:
                    headers["x-gmkerl-type"] = "fix_min"; break;
                case GmkerlType.fixScale:
                    headers["x-gmkerl-type"] = "fix_scale"; break;
                default: break;
            }
            if(gmkerl.type != GmkerlType.ignore)
                headers["x-gmkerl-value"] = gmkerl.value;
            if(gmkerl.quality > 0)
                headers["x-gmkerl-quality"] = gmkerl.quality.to!string;
            switch(gmkerl.unsharp) {
                case GmkerlSwitch.on:
                    headers["x-gmkerl-unsharp"] = "true"; break;
                case GmkerlSwitch.off:
                    headers["x-gmkerl-unsharp"] = "false"; break;
                default: break;
            }
            if(gmkerl.thumbnail !is null)
                headers["x-gmkerl-thumbnail"] = gmkerl.thumbnail;
            switch(gmkerl.exifSwitch) {
                case GmkerlSwitch.on:
                    headers["x-gmkerl-exif-switch"] = "true"; break;
                case GmkerlSwitch.off:
                    headers["x-gmkerl-exif-switch"] = "false"; break;
                default: break;
            }
            if(gmkerl.crop !is null)
                headers["x-gmkerl-crop"] = gmkerl.crop;
            switch(gmkerl.rotate) {
                case GmkerlRotate.rauto:
                    headers["x-gmkerl-rotate"] = "auto"; break;
                case GmkerlRotate.r90:
                    headers["x-gmkerl-rotate"] = "90"; break;
                case GmkerlRotate.r180:
                    headers["x-gmkerl-rotate"] = "180"; break;
                case GmkerlRotate.r270:
                    headers["x-gmkerl-rotate"] = "270"; break;
                default: break;
            }
            if(gmkerl.watermarkText !is null)
                headers["x-gmkerl-watermark-text"] = gmkerl.watermarkText;
            if(gmkerl.watermarkFont !is null)
                headers["x-gmkerl-watermark-font"] = gmkerl.watermarkFont;
            if(gmkerl.watermarkSize > 0)
                headers["x-gmkerl-watermark-size"] = gmkerl.watermarkSize.to!string;
            if(gmkerl.watermarkAlign !is null)
                headers["x-gmkerl-watermark-align"] = gmkerl.watermarkAlign;
            if(gmkerl.watermarkMargin !is null)
                headers["x-gmkerl-watermark-margin"] = gmkerl.watermarkMargin;
            if(gmkerl.watermarkOpacity > -1)
                headers["x-gmkerl-watermark-opacity"] = gmkerl.watermarkOpacity.to!string;
            if(gmkerl.watermarkColor !is null)
                headers["x-gmkerl-watermark-color"] = gmkerl.watermarkColor;
            if(gmkerl.watermarkBorder !is null)
                headers["x-gmkerl-watermark-border"] = gmkerl.watermarkBorder;
        }
        if (md5Verify) headers["Content-MD5"] = toHexString!(LetterCase.lower, Order.increasing)(md5Of(data));
        if (contentType !is null) headers["Content-Type"] = contentType;
        if (secret !is null) headers["Content-Secret"] = secret;
        auto r = requestInternal(path, HTTPMethod.PUT, headers, data);
        if(r.ret.statusCode == 200) {
            auto p = "width" in r.response;
            if(p) res.width = (*p).to!int;
            p = "height" in r.response;
            if(p) res.height = (*p).to!int;
            p = "frames" in r.response;
            if(p) res.frames = (*p).to!int;
            p = "file-type" in r.response;
            if(p) res.fileType = *p;
        }
        return r.ret;
    }

    /**
     * Download a file
     *
     * Params:
     *   path        = remote path
     *   content     = file content downloaded
     */
    Ret downloadFile(string path, ref ubyte[] content) {
        auto r = requestInternal(path, HTTPMethod.GET);
        if(r.ret.statusCode == 200)
            content = r.bodyRaw;
        return r.ret;
    }

    /**
     * Download a file
     *
     * Params:
     *   path        = remote path
     *   localFile   = local path for the downloaded file
     */
    Ret downloadFile(string path, string localFile) {
        ubyte[] content;
        auto ret = downloadFile(path, content);
        if(ret.statusCode == 200)
            write(localFile, content);
        return ret;
    }

    /**
     * Get information for a file
     *
     * Params:
     *   path        = remote path
     *   type        = receives 'Content-Type'
     *   size        = receives file size in bytes
     *   timestamp   = receives file time in unix timestamp
     */
    Ret fileInfo(string path, ref string type, ref ulong size, ref ulong timestamp) {
        auto r = requestInternal(path, HTTPMethod.HEAD);
        if(r.ret.statusCode == 200) {
            auto p = "file-type" in r.response;
            if(p) type = *p;
            p = "file-size" in r.response;
            if(p) size = (*p).to!ulong;
            p = "file-date" in r.response;
            if(p) timestamp = (*p).to!ulong;
        }
        return r.ret;
    }

    /**
     * Delete a file
     *
     * Params:
     *   path        = remote file path to delete
     */
    Ret deleteFile(string path) {
        return requestInternal(path, HTTPMethod.DELETE).ret;
    }

    /**
     * Create a directory
     *
     * Params:
     *   path        = remote directory path to create
     *   autoMake    = make directories recursively
     */
    Ret makeDir(string path, bool autoMake = false) {
        return requestInternal(path, HTTPMethod.POST, ["folder": "true", "mkdir": autoMake ? "true" : "false"]).ret;
    }

    /**
     * List files in a directory
     *
     * Params:
     *   path        = remote directory path to list
     *   files       = receive files' information
     */
    Ret listDir(string path, ref FileInfo[] files) {
        auto r = requestInternal(path, HTTPMethod.GET);
        if(r.ret.statusCode == 200) {
            auto content = cast(string)r.bodyRaw;
            foreach(l; content.split('\n')) {
                auto fields = l.split('\t');
                if(fields.length >= 4) {
                    files ~= FileInfo(fields[0], fields[1] == "F", fields[2].to!ulong, fields[3].to!ulong);
                }
            }
        }
        return r.ret;
    }

    /**
     * List files in a directory throught iterator
     *
     * Params:
     *   path        = remote directory path to list
     *   iter        = reference to the iterator
     *   callback    = callback delegate to receive file info during iteration
     *
     * Note:
     *   if no more files, Ret.errorCode is 1.
     */
    Ret listDir(string path, ref DirIterator iter, void delegate(ref FileInfo fileInfo) callback) {
        immutable string iterEnd = "g2gCZAAEbmV4dGQAA2VvZg";
        string[string] headers = ["X-List-Limit": (iter.limit == 0 ? 100 : iter.limit).to!string, "X-List-Order": (iter.order ? "desc" : "asc")];
        if(iter.listIter.length > 0)
            headers["X-List-Iter"] = iter.listIter;
        auto r = requestInternal(path, HTTPMethod.GET, headers);
        if(r.ret.statusCode == 200) {
            auto content = cast(string)r.bodyRaw;
            foreach(l; content.split('\n')) {
                auto fields = l.split('\t');
                if(fields.length >= 4) {
                    FileInfo finfo = FileInfo(fields[0], fields[1] == "F", fields[2].to!ulong, fields[3].to!ulong);
                    callback(finfo);
                }
            }

            auto p = "list-iter" in r.response;
            if (p !is null) {
                iter.listIter = *p;
                if (iter.listIter == iterEnd)
                    r.ret.errorCode = 1;
            } else {
                // TODO: add a special error code to implify that no x-upyun-list-iter in response header
                r.ret.errorCode = -1;
            }
        }
        return r.ret;
    }

    /**
     * Get bucket space usage
     *
     * Params:
     *   path        = remote directory path
     *   bytes       = receive bytes used
     */
    Ret getUsage(string path, ref ulong bytes) {
        auto r = requestInternal(path ~ ((path.length == 0 || path[$-1] != '/') ? "/?usage" : "?usage"), HTTPMethod.GET);
        if(r.ret.statusCode == 200)
            bytes = (cast(string)r.bodyRaw).to!ulong;
        return r.ret;
    }

    /**
     * Purge CDN caches
     *
     * Params:
     *   urls        = list of urls, please supply COMPLETE http urls
     */
    int purge(string[] urls) {
        int statusCode = -1;
        string purl = urls.join("\n");
        requestHTTP(purge_url_, (scope req) {
            req.method = HTTPMethod.POST;
            string dt = rfc1123Time();
            req.headers["Date"] = dt;
            req.headers["Authorization"] = "UpYun %s:%s:%s".format(config_.bucket, config_.user,
                toHexString!(LetterCase.lower, Order.increasing)(md5Of("%s&%s&%s&%s".format(
                purl, config_.bucket, dt, passhash_))));
            req.writeFormBody(["purge": purl]);
        }, (scope res) {
            statusCode = res.statusCode;
            std.stdio.writefln("%s", res.bodyReader.readAllUTF8());
        });
        return statusCode;
    }

private:
    RetInternal requestInternal(string path, HTTPMethod method, const string[string] headers = null, ubyte[] data = []) {
        RetInternal result;
        string basepath = "/" ~ config_.bucket ~ path;
        string url = (config_.useHttps ? "https://" : "http://") ~ api_url_[config_.endpoint] ~ basepath;
        requestHTTP(url, (scope req) {
            req.method = method;
            string dt = rfc1123Time();
            req.headers["Host"] = api_url_[config_.endpoint];
            req.headers["Date"] = dt;
            req.headers["Authorization"] = "UpYun %s:%s".format(config_.user,
                toHexString!(LetterCase.lower, Order.increasing)(md5Of("%s&%s&%s&%s&%s".format(
                method, basepath, dt, data.length, passhash_))));
            foreach(k, ref v; headers) {
                req.headers[k] = v;
            }
            if(data.length > 0)
                req.bodyWriter.write(data);
        }, (scope res) {
            result.ret.statusCode = res.statusCode;
            if(result.ret.statusCode != 200) {
                try {
                    auto j = res.readJson();
                    auto code = j.code;
                    if(code.type == Json.Type.int_)
                        result.ret.errorCode = code.to!int;
                    auto msg = j.msg;
                    if(msg.type == Json.Type.string)
                        result.ret.errorMsg = msg.to!string;
                } catch { }
            } else {
                try {
                    result.bodyRaw = res.bodyReader.readAll();
                } catch {}
            }
            foreach(k, v; res.headers) {
                if(k.startsWith("x-upyun-"))
                    result.response[k[8..$]] = v;
            }
        });
        return result;
    }

    static string[] daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    static string[] monthsOfYear = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    string rfc1123Time() {
        auto dt = cast(DateTime)Clock.currTime(UTC());
        return format("%s, %02d %s %04d %02d:%02d:%02d GMT",
                daysOfWeek[dt.dayOfWeek],
                dt.day,
                monthsOfYear[dt.month - 1],
                dt.year,
                dt.hour,
                dt.minute,
                dt.second);
    }
}

/**
 * Create UpYun object
 */
public UpYun createUpYun(ref UpYunConfig config) {
    return new UpYun(config);
}
