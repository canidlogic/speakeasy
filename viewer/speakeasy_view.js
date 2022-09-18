"use strict";

/*
 * speakeasy_view.js
 * =================
 * 
 * JavaScript code for the SpeakEasy viewer app.
 * 
 * You must also load scavenger.js as a prerequisite for this module.
 */

/*
 * ===================
 * SpeakEasyNode class
 * ===================
 * 
 * This class is used by the main program module to represent a parsed
 * directory and to handle image loading.
 * 
 * Create a new instance like this, linking it to the Scavenger decoder
 * that holds the Scavenger file:
 * 
 *    let node = new SpeakEasyNode(scavenger_decoder, ["image"]);
 * 
 * Also pass an array containing strings specifying which resource
 * classes you can handle.  Resource classes are "image" "video" "audio"
 * and "text".  Unrecognized resource classes are ignored.  Only files
 * of the given resource class will be loaded.  (Note, however, that
 * thumbnails are always loaded, even if you don't specify "image".)
 * 
 * You can figure out what resource classes a particular node instance
 * was constructed to support like this:
 * 
 *    if (node.supports("image")) {
 *      ...
 *    }
 * 
 * You must load a directory before the object can be used.  Pass the
 * object ID within the Scavenger decoder of the node that you want to
 * load.  Node that object #0 is always supposed to be the root node.
 * The load operation is asynchronous.
 * 
 *    await node.load(5);
 * 
 * IMPORTANT:  Unfortunately, object URLs are allocated and freed
 * manually, which doesn't work well with JavaScript's automatic memory
 * management.  Once you are done with a node, explicitly close it like
 * this:
 * 
 *    node.close();
 * 
 * Closing will release all the object URLs that were allocated.  The
 * object will be returned to an unloaded state.
 * 
 * You can check whether the object instance has loaded correctly using
 * the following:
 * 
 *    if (node.isLoaded()) {
 *      ...
 *    }
 * 
 * Do NOT poll this function in a loop to check for loading completion.
 * Asynchronously wait for the load() procedure to finish instead.
 * 
 * When the node is loaded, you can access the trail like this:
 * 
 *    for(let i = 0; i < node.trailCount(); i++) {
 *      const trailItem   = node.trailItem(i);
 *      const dirObjectID = trailItem.objectID;
 *      const dirName     = trailItem.dirName;
 *      ...
 *    }
 * 
 * Each of the trailItem.objectID values can then be passed to the load
 * method of a SpeakEasyNode to load those directories.  The first
 * directory in the trail is the root directory and the last directory
 * in the trail is the current directory.  There may be only one
 * directory in the trail, in which case the root directory is the
 * current directory.  However, there will always be at least one
 * directory in the trail.
 * 
 * When the node is loaded, you can access the subdirectories like this:
 * 
 *    for(let i = 0; i < node.folderCount(); i++) {
 *      const folder         = node.folderItem(i);
 *      const folderObjectID = folder.objectID;
 *      const folderName     = folder.dirName;
 *      ...
 *    }
 * 
 * The returned folder item objects have the exact same structure as
 * trail items.  The folder list will always be in a properly sorted
 * order with folders order ascending by name.  The folder list might be
 * empty if there are no subfolders.
 * 
 * Files are loaded progressively, because loading them all at once
 * takes too long for large directories.
 * 
 * After construction, none of the files will be loaded.  You load files
 * by indicating the sorting order and the maximum number of files that
 * can be loaded at once:
 * 
 *    await node.loadFiles("name_asc", 10);
 * 
 * The sorting order does NOT need to be the same each time.  If you
 * change the sorting order, the file list will be reloaded from the
 * start; however, files that have already been loaded will remain in
 * the loaded cache.  More than the specified number of files may be
 * loaded if files have already been cached.
 * 
 * The current sorting order can be retrieved like so:
 * 
 *    const sort_type = node.getSortType();
 * 
 * You can check whether all files have been loaded with the following:
 * 
 *    if (node.hasAllFiles()) {
 *      ...
 *    }
 * 
 * Once you have loaded all the files, hasAllFiles will always return
 * true for future calls, even if you change the sorting order, because
 * everything will be in the cache.
 * 
 * You can loop over the loaded files like this:
 * 
 *    for(let i = 0; i < node.fileCount(); i++) {
 *      const file      = node.fileItem(i);
 *      const fileClass = file.resourceClass;
 *      const fileURL   = file.dataURL;
 *      const thumbURL  = file.thumbURL;
 *      const fileName  = file.fileName;
 *      const fileTime  = file.fileTime;
 *      const fileDesc  = file.fileDesc;
 *      ...
 *    }
 * 
 * This will only loop over LOADED files.  You must use loadFiles() to
 * progressively load the file contents.  The resourceClass is
 * guaranteed to only be one of the supported resource classes that was
 * specified to the constructor.
 */

/*
 * Constructor
 * -----------
 */

/*
 * The object starts out unloaded, but linked to a specific Scavenger
 * decoder.
 * 
 * The decoder must be loaded.
 * 
 * You must also specify an array of strings indicating which resource
 * classes you can support.  Files of other resource classes will be
 * filtered out and not appear in file listings.  (But thumbnails will
 * always be present, even if you don't specify you support "image".)
 * The valid resource classes are "image" "video" "audio" "text".
 * 
 * Parameters:
 * 
 *   decoder : Scavenger - the loaded Scavenger decoder instance
 * 
 *   resclass : array of string - the supported file classes
 */
function SpeakEasyNode(decoder, resclass) {
  // Check parameters
  if (!(decoder instanceof Scavenger)) {
    throw new TypeError();
  }
  if (!(resclass instanceof Array)) {
    throw new TypeError();
  }
  for(let i = 0; i < resclass.length; i++) {
    if (typeof(resclass[i]) !== "string") {
      throw new TypeError();
    }
  }
  
  // Check state
  if (!decoder.isLoaded()) {
    throw new Error("Decoder must be loaded");
  }
  
  // _loaded indicates whether loaded
  this._loaded = false;
  
  // _decoder will store the Scavenger decoder
  this._decoder = decoder;
  
  // _useImage _useVideo _useAudio _useText are booleans indicating
  // which of those resource classes are supported
  this._useImage = false;
  this._useVideo = false;
  this._useAudio = false;
  this._useText  = false;
  
  for(let i = 0; i < resclass.length; i++) {
    if (resclass[i] === "image") {
      this._useImage = true;
      
    } else if (resclass[i] === "video") {
      this._useVideo = true;
      
    } else if (resclass[i] === "audio") {
      this._useAudio = true;
      
    } else if (resclass[i] === "text") {
      this._useText = true;
    }
  }
  
  // _opid is incremented each time an asynchronous load completes, each
  // time the object is unloaded, and each time a loadFiles operation
  // begins, and is used for canceling loadFiles operations that are no
  // longer needed
  this._opid = 0;
}

/*
 * Private class functions
 * -----------------------
 */

/*
 * Check whether the given parameter is a finite integer.
 * 
 * Parameters:
 * 
 *   i - the value to check
 * 
 * Return:
 * 
 *   true if finite integer, false if not
 */
SpeakEasyNode._isInteger = function(i) {
  if (typeof(i) !== "number") {
    return false;
  }
  if (!isFinite(i)) {
    return false;
  }
  if (Math.floor(i) !== i) {
    return false;
  }
  return true;
};

/*
 * Attempt to convert an unsigned JSON integer into a numeric integer.
 * 
 * JSON integers might be stored as numeric values, but very large
 * values might be instead stored as unsigned decimal strings.  This
 * function will handle both cases.
 * 
 * This function does not handle negative values.
 * 
 * Parameter:
 * 
 *   i - the value to attempt to convert to integer
 * 
 * Return:
 * 
 *   the numeric value of the integer or null if conversion failed
 */
SpeakEasyNode._jsonInteger = function(i) {
  // If already an integer, return that
  if (SpeakEasyNode._isInteger(i)) {
    return i;
  }
  
  // Not an integer, so the only other case is a string
  if (typeof(i) !== "string") {
    return null;
  }
  
  // We can always safely represent 15 decimal digits, which is in the
  // maximum safe integer range (2^53 - 1), and can also represent
  // file sizes over 900 TiB large, which should be sufficient
  if ((i !== "0") && (!((/^[1-9][0-9]{0,14}$/).test(i)))) {
    return null;
  }
  
  // Convert to numeric integer
  i = parseInt(i, 10);
  if (!SpeakEasyNode._isInteger(i)) {
    throw new Error("Unexpected");
  }
  
  // Return converted integer
  return i;
};

/*
 * Public instance functions
 * -------------------------
 */

/*
 * Check whether this node is in a loaded state.
 * 
 * Do NOT poll this function to check for load completion.
 * 
 * This returns true only if node is fully loaded.  false is returned if
 * unloaded.
 * 
 * This function can be used at any time.
 * 
 * Return:
 * 
 *   true if fully loaded, false otherwise
 */
SpeakEasyNode.prototype.isLoaded = function() {
  return this._loaded;
};

/*
 * Check whether this node object was constructed with support for the
 * given resource class.
 * 
 * This call can be used at any time.  Unrecognized resource class names
 * will just return false.  Recognized are "image" "video" "audio" and
 * "text".
 * 
 * Parameters:
 * 
 *   restype : string - a resource class name
 * 
 * Return:
 * 
 *   true if supported, false if not
 */
SpeakEasyNode.prototype.supports = function(restype) {
  // Check parameter
  if (typeof(restype) !== "string") {
    throw new TypeError();
  }
  
  // Get result
  let result = false;
  
  if (restype === "image") {
    result = this._useImage;
  
  } else if (restype === "video") {
    result = this._useVideo;
    
  } else if (restype === "audio") {
    result = this._useAudio;
    
  } else if (restype === "text") {
    result = this._useText;
  }
  
  return result;
};

/*
 * Asynchronously load this node from a particular object ID in the
 * Scavenger decoder that was provided to the constructor.
 * 
 * This function does not load any of the files in the node.
 * 
 * The state of the object instance is only changed if this load
 * operation completes successfully.  Otherwise, it remains unchanged.
 * 
 * If the object is already loaded, then this function will
 * asynchronously begin a new load operation.  If the new load fails,
 * the object remains in its previously loaded state.  If the new load
 * succeeds, the object is closed and then immediately opened with the
 * new load state.
 * 
 * Parameters:
 * 
 *   object_id : integer - the ID of the object containing the node to
 *   load
 */
SpeakEasyNode.prototype.load = async function(object_id) {
  // Check parameter
  if (!SpeakEasyNode._isInteger(object_id)) {
    throw new TypeError();
  }
  if ((object_id < 0) || (object_id >= this._decoder.getCount())) {
    throw new Error("Object ID out of range");
  }
  
  // First thing we want to do is load and parse the JSON
  let json = await this._decoder.fetchUTF8(object_id);
  json = JSON.parse(json);
  
  // Get a collator for sorting in alphabetic order according to default
  // system locale, with numeric sorting enabled so that 1 < 2 < 10
  const col = new Intl.Collator(undefined, {
    "numeric": true
  });
  
  // trail will store the trail array
  if (!("trail" in json)) {
    throw new Error("Missing trail property");
  }
  const trail = json.trail;
  if (!(trail instanceof Array)) {
    throw new Error("trail must be array");
  }
  if (!(trail.length > 0)) {
    throw new Error("trail must not be empty");
  }
  for(let i = 0; i < trail.length; i++) {
    const a = trail[i];
    if (!(a instanceof Array)) {
      throw new Error("trail components must be arrays");
    }
    if (a.length !== 2) {
      throw new Error("trail components must be length 2");
    }
    a[0] = SpeakEasyNode._jsonInteger(a[0]);
    if (a[0] === null) {
      throw new Error("First trail component must be integer");
    }
    if (!((a[0] >= 0) && (a[0] < this._decoder.getCount()))) {
      throw new Error("Trail refers to non-existent object");
    }
    if (typeof(a[1]) !== "string") {
      throw new Error("Trail name must be string");
    }
  }
  
  // folders will store the subfolders list
  if (!("folders" in json)) {
    throw new Error("Missing folders property");
  }
  const folders = json.folders;
  if (!(folders instanceof Array)) {
    throw new Error("folders must be array");
  }
  for(let i = 0; i < folders.length; i++) {
    const a = folders[i];
    if (!(a instanceof Array)) {
      throw new Error("folders components must be arrays");
    }
    if (a.length !== 2) {
      throw new Error("folders components must be length 2");
    }
    a[0] = SpeakEasyNode._jsonInteger(a[0]);
    if (a[0] === null) {
      throw new Error("First folder component must be integer");
    }
    if (!((a[0] >= 0) && (a[0] < this._decoder.getCount()))) {
      throw new Error("Folder refers to non-existent object");
    }
    if (typeof(a[1]) !== "string") {
      throw new Error("Folder name must be string");
    }
  }
  
  // folders must be sorted in ascending alphabetic order
  folders.sort((a, b) => col.compare(a[1], b[1]));
  
  // filtered will store the filtered list of files, with only files of
  // supported classes included
  if (!("files" in json)) {
    throw new Error("Missing files property");
  }
  if (!(json.files instanceof Array)) {
    throw new Error("files must be array");
  }
  const filtered = [];
  for(let i = 0; i < json.files.length; i++) {
    // Get current element
    const a = json.files[i];
    
    // Check it is an object
    if (typeof(a) !== "object") {
      throw new Error("files must be objects");
    }
    
    // Check it has a class field that is a string
    if (!("rclass" in a)) {
      throw new Error("files must have rclass");
    }
    if (typeof(a.rclass) !== "string") {
      throw new Error("rclass must be string");
    }
    
    // Skip if not supported
    if (!this.supports(a.rclass)) {
      continue;
    }
    
    // rbin and tbin are integers and must refer to valid objects
    if (!("rbin" in a)) {
      throw new Error("files must have rbin");
    }
    if (!("tbin" in a)) {
      throw new Error("files must have tbin");
    }
    a.rbin = SpeakEasyNode._jsonInteger(a.rbin);
    a.tbin = SpeakEasyNode._jsonInteger(a.tbin);
    if (a.rbin === null) {
      throw new Error("file.rbin must be an integer");
    }
    if (a.tbin === null) {
      throw new Error("file.tbin must be an integer");
    }
    if (!((a.rbin >= 0) && (a.rbin < this._decoder.getCount()))) {
      throw new Error("file.rbin out of range");
    }
    if (!((a.tbin >= 0) && (a.tbin < this._decoder.getCount()))) {
      throw new Error("file.tbin out of range");
    }
    
    // rmime tmime and rname must exist and be strings
    if (!("rmime" in a)) {
      throw new Error("files must have rmime");
    }
    if (!("tmime" in a)) {
      throw new Error("files must have tmime");
    }
    if (!("rname" in a)) {
      throw new Error("files must have rname");
    }
    
    if (typeof(a.rmime) !== "string") {
      throw new Error("files.rmime must be string");
    }
    if (typeof(a.tmime) !== "string") {
      throw new Error("files.tmime must be string");
    }
    if (typeof(a.rname) !== "string") {
      throw new Error("files.rname must be string");
    }
    
    // rtime must exist and be string
    if (!("rtime" in a)) {
      throw new Error("files must have rtime");
    }
    if (typeof(a.rtime) !== "string") {
      throw new Error("files.rtime must be string");
    }
    
    // rtime must have valid fixed format
    if (!((/^\d{4}-\d{2}-\d{2} \d{2}\:\d{2}\:\d{2}$/).test(a.rtime))) {
      throw new Error("files.rtime must be YYYY-MM-DD HH:MM:SS");
    }
    
    // If desc not defined, define it as empty string
    if (!("desc" in a)) {
      a.desc = "";
    }
    
    // Make sure desc is string
    if (typeof(a.desc) !== "string") {
      throw new Error("files.desc must be string");
    }
    
    // If we got here, then add it to the array
    filtered.push(a);
  }
  
  // Begin with filtered sorted by name ascending
  filtered.sort((a, b) => col.compare(a.rname, b.rname));
  
  // We are ready, so close the object and set _trail _folders and
  // _filtered to the arrays we just loaded and checked
  this.close();
  this._trail    = trail;
  this._folders  = folders;
  this._filtered = filtered;
  
  // The _url map maps base-10 representations of binary object IDs to
  // allocated data URLs; we haven't loaded anything yet so this will
  // start out empty
  this._url = {};
  
  // _sort is the sort order of _filtered; we have _filtered sorted by
  // "name_asc" right now
  this._sort = "name_asc";
  
  // _loadCount is the number of files in _filtered that have been
  // loaded such that their binaries and thumbnail binaries appear in
  // the _url mapping; since this mapping is empty to begin with, we
  // know we start out with nothing
  this._loadCount = 0;
  
  // Increase _opid to cancel any loadFiles operation in progress
  this._opid = this._opid + 1;
  
  // Set _loaded flag
  this._loaded = true;
};

/*
 * If this node is loaded, return it to an unloaded state.
 * 
 * You should close each SpeakEasyNode instance before releasing it so
 * that its object URLs get freed properly.  JavaScript's automatic
 * memory management does NOT work for object URLs.
 * 
 * Nothing happens if the object is already unloaded.
 */
SpeakEasyNode.prototype.close = function() {
  // Only proceed if loaded
  if (this._loaded) {
    // Get all URL keys and release all URLs
    const keys = Object.keys(this._url);
    for(let x = 0; x < keys.length; x++) {
      URL.revokeObjectURL(this._url[keys[x]]);
      delete this._url[keys[x]];
    }
    
    // Clear arrays
    this._trail    = null;
    this._folders  = null;
    this._filtered = null;
    
    // Clear loaded flag
    this._loaded = false;
    
    // Increase _opid to cancel any loadFiles operation in progress
    this._opid = this._opid + 1;
  }
};

/*
 * Attempt to load some files for the current node.
 * 
 * The node must be loaded to use this function.  At the start of the
 * function, an internal _opid counter will be incremented and the value
 * stored.  This internal _opid counter is also incremented each time a
 * successful load() is performed and each time close() unloads the
 * object instance.  If during this asynchronous function it detects
 * that the _opid has changed, then it will return to caller and proceed
 * no further in loading.  This prevents multiple loading operations,
 * and also prevents loading operations that are no longer relevant.
 * 
 * sortType is the way the files should be sorted.  It can be one of:
 * "name_asc" "name_desc" "date_asc" "date_desc".
 * 
 * maxLoad is the maximum number of new files that can be loaded in this
 * operation.  It must be an integer that is greater than zero.  Files
 * that are already cached do not count against this limit.
 * 
 * Parameters:
 * 
 *   sortType : string - the sorting order
 * 
 *   maxLoad : integer - the maximum number of new files to load
 */
SpeakEasyNode.prototype.loadFiles = async function(sortType, maxLoad) {
  // Check parameters
  if (typeof(sortType) !== "string") {
    throw new TypeError();
  }
  if (!SpeakEasyNode._isInteger(maxLoad)) {
    throw new TypeError();
  }
  if (!(maxLoad > 0)) {
    throw new Error("maxLoad must be more than zero");
  }
  
  // Check state
  if (!this._loaded) {
    throw new Error("Object must be loaded");
  }
  
  // Increase _opid and store the _opid that must remain while this
  // operation is in progress
  this._opid = this._opid + 1;
  const current_op = this._opid;
  
  // If sortType has changed, re-sort the _filtered array
  if (this._sort !== sortType) {
    // Get a collator for sorting in alphabetic order according to
    // default system locale, with numeric sorting enabled so that\
    // 1 < 2 < 10
    const col = new Intl.Collator(undefined, {
      "numeric": true
    });
    
    // Handle the specific sort
    if ((sortType === "name_asc") || (sortType === "name_desc")) {
      this._filtered.sort((a, b) => col.compare(a.rname, b.rname));
      
    } else if ((sortType === "date_asc") ||
                (sortType === "date_desc")) {
      this._filtered.sort((a, b) => col.compare(a.rtime, b.rtime));
      
    } else {
      throw new Error("Unrecognized sort type");
    }
    
    // If we have a descending sort, reverse the order
    if ((sortType === "name_desc") || (sortType === "date_desc")) {
      this._filtered.reverse();
    }
    
    // Update the sort type
    this._sort = sortType;
  }
  
  // Reset _loadCount to zero
  this._loadCount = 0;
  
  // Go through the list and load what we can
  for(let x = 0; x < this._filtered.length; x++) {
    // Get entry
    const a = this._filtered[x];
    
    // If this entry is loaded, increase the _loadCount and skip to the
    // next
    if ((a.rbin.toString(10) in this._url) &&
        (a.tbin.toString(10) in this._url)) {
      this._loadCount = this._loadCount + 1;
      continue;
    }
    
    // This entry is not fully loaded, so check if still have space in
    // maxLoad for another load operation, stopping if we do not
    if (!(maxLoad > 0)) {
      return;
    }
    
    // Now we need to load it
    for(let y = 0; y < 2; y++) {
      // Get the object ID we need to load and its MIME type
      let objid;
      let objmime;
      
      if (y === 0) {
        objid = a.rbin;
        objmime = a.rmime;
        
      } else if (y === 1) {
        objid = a.tbin;
        objmime = a.tmime;
        
      } else {
        throw new Error("Unexpected");
      }
      
      // If already loaded, skip it
      if (objid.toString(10) in this._url) {
        continue;
      }
      
      // Attempt to load
      const blob = await this._decoder.fetch(objid, objmime);
      
      // We just did an asynchronous wait, so it _opid no longer matches
      // current_op we need to stop right here
      if (current_op !== this._opid) {
        return;
      }
      
      // If we got here, we are still current, so store the loaded blob
      // in the cache with a newly constructed data URL, if not already
      // there
      if (!(objid.toString(10) in this._url)) {
        this._url[objid.toString(10)] = URL.createObjectURL(blob);
      }
    }
  
    // Increase _loadCount and decrease maxLoad before looping again
    this._loadCount = this._loadCount + 1;
    maxLoad--;
  }
};

/*
 * Return the current sort order used for the files in this object.
 * 
 * The object must be loaded.
 * 
 * Return:
 * 
 *   the sort order as a string
 */
SpeakEasyNode.prototype.getSortType = function() {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Return desired information
  return this._sort;
};

/*
 * Return how many items there are in the trail.
 * 
 * The object must be loaded.  The return value will be at least one.
 * 
 * Return:
 * 
 *   the number of items in the trail
 */
SpeakEasyNode.prototype.trailCount = function() {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Return desired information
  return this._trail.length;
};

/*
 * Return how many items there are in the subfolders array.
 * 
 * The object must be loaded.  The return value will be zero or greater.
 * 
 * Return:
 * 
 *   the number of items in the trail
 */
SpeakEasyNode.prototype.folderCount = function() {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Return desired information
  return this._folders.length;
};

/*
 * Return how many file items are currently loaded.
 * 
 * The object must be loaded.  The return value will be zero or greater.
 * 
 * This is NOT the total number of files.  It only refers to how many
 * files have been loaded and are available.  Use hasAllFiles() to check
 * whether all files have been loaded (in which case this function WILL
 * return the total file count), and use loadFiles() to progressively
 * load more files.
 * 
 * Files that are filtered out because they do not have a supported
 * multimedia class (as was specified to the constructor) will never be
 * counted here.
 * 
 * Return:
 * 
 *   the number of currently loaded file items
 */
SpeakEasyNode.prototype.fileCount = function() {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Return desired information
  return this._loadCount;
};

/*
 * Check whether all files have been loaded yet.
 * 
 * The object must be loaded.  The return value will be zero or greater.
 * 
 * Files are loaded progressively by calling the loadFiles() function.
 * fileCount() returns how many files are currently available.  This
 * function, hasAllFiles() checks whether all files have been loaded.
 * 
 * Once all files are loaded, they remain all loaded, even if you call
 * loadFiles() with a different sorting order.
 * 
 * Return:
 * 
 *   true if all files loaded, false if not
 */
SpeakEasyNode.prototype.hasAllFiles = function() {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Return desired information
  if (this._loadCount >= this._filtered.length) {
    return true;
  } else {
    return false;
  }
};

/*
 * Return a specific item in the trail.
 * 
 * i is the index of the trail item.  It must be at least zero and less
 * than the value returned by trailCount().  The object must be loaded.
 * 
 * The return value will be an object with an integer property
 * "objectID" that stores the object ID of the directory, and a string
 * property "dirName" that stores the name of the directory.
 * 
 * The first item of the trail is the root directory and the last item
 * of the trail is the current directory.  If there is only one item in
 * the trail, it is the root directory, which is the current directory.
 * 
 * Parameters:
 * 
 *   i : integer - the index of the trail item
 * 
 * Return:
 * 
 *   an object representing the trail item
 */
SpeakEasyNode.prototype.trailItem = function(i) {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Check parameter
  if (!SpeakEasyNode._isInteger(i)) {
    throw new TypeError();
  }
  if (!((i >= 0) && (i < this._trail.length))) {
    throw new Error("Trail index out of range");
  }
  
  // Return the desired information
  return {
    "objectID": this._trail[i][0],
    "dirName" : this._trail[i][1]
  };
};

/*
 * Return a specific item in the subfolder list.
 * 
 * i is the index of the folder item.  It must be at least zero and less
 * than the value returned by folderCount().  The object must be loaded.
 * 
 * The return value will be an object with an integer property
 * "objectID" that stores the object ID of the directory, and a string
 * property "dirName" that stores the name of the directory.
 * 
 * The folders are sorted in ascending order of folder name in the list.
 * 
 * Parameters:
 * 
 *   i : integer - the index of the trail item
 * 
 * Return:
 * 
 *   an object representing the trail item
 */
SpeakEasyNode.prototype.folderItem = function(i) {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Check parameter
  if (!SpeakEasyNode._isInteger(i)) {
    throw new TypeError();
  }
  if (!((i >= 0) && (i < this._folders.length))) {
    throw new Error("Trail index out of range");
  }
  
  // Return the desired information
  return {
    "objectID": this._folders[i][0],
    "dirName" : this._folders[i][1]
  };
};

/*
 * Return a specific item in the currently loaded files list.
 * 
 * i is the index of the file item.  It must be at least zero and less
 * than the value returned by fileCount().  The object must be loaded.
 * 
 * Note that this is only able to access files that have been loaded.
 * You must use loadFiles() to progressively load files.  The file list
 * is only complete when hasAllFiles() returns true.
 * 
 * Files that have unsupported media classes as according to the
 * supported media list provided to the constructor are never returned
 * by this function.
 * 
 * The return value will be an object with the following properties:
 * 
 *   resourceClass - "image" "audio" "video" or "text"
 *   dataURL - URL to the actual data file
 *   thumbURL - URL to the thumbnail image data file
 *   fileName - the name of the file as a string
 *   fileTime - the time of the file as a YYYY-MM-DD HH:MM:SS string
 *   fileDesc - description as a string, empty string if none
 * 
 * The files will be sorted in the list according to the sort order most
 * recently used with the loadFiles() function.  You can call
 * loadFiles() again to change the sort order, even if all the files are
 * already loaded.
 * 
 * Parameters:
 * 
 *   i : integer - the index of the file item
 * 
 * Return:
 * 
 *   an object representing the file item
 */
SpeakEasyNode.prototype.fileItem = function(i) {
  // Check state
  if (!this._loaded) {
    throw new Error("Invalid state");
  }
  
  // Check parameter
  if (!SpeakEasyNode._isInteger(i)) {
    throw new TypeError();
  }
  if (!((i >= 0) && (i < this._loadCount))) {
    throw new Error("File index out of range");
  }
  
  // Return the desired information
  return {
    "resourceClass": this._filtered[i].rclass,
    "dataURL": this._url[this._filtered[i].rbin.toString(10)],
    "thumbURL": this._url[this._filtered[i].tbin.toString(10)],
    "fileName": this._filtered[i].rname,
    "fileTime": this._filtered[i].rtime,
    "fileDesc": this._filtered[i].desc
  };
};

/*
 * ===================
 * Main program module
 * ===================
 */

// Wrap everything in an anonymous function that we immediately invoke
// after it is declared -- this prevents anything from being implicitly
// added to global scope
(function() {

  /*
   * Constants
   * =========
   */
  
  /*
   * Array storing all the top-level DIVs.
   */
  const DIV_LIST = ["divLoading", "divLoadError", "divLoadDialog",
                    "divMain"];
  
  /*
   * The initial maximum number of files that are loaded per directory.
   */
  const INITIAL_FILES = 5;
  
  /*
   * The maximum number of files that are loaded each time the user
   * explicitly chooses to load more files.
   */
  const MORE_FILES = 10;
  
  /*
   * Local data
   * ==========
   */
  
  /*
   * When a file is loaded, this object will store the Scavenger
   * decoder instance.
   * 
   * When no file is loaded, this is null.
   */
  let m_data = null;
  
  /*
   * When a file is loaded, this SpeakEasyNode object instance is used
   * for decoding directories.
   */
  let m_node = null;
  
  /*
   * These variables store how many files are already being displayed in
   * the current page, and according to what sort order.
   * 
   * m_file_count is the number of files displayed.  m_file_sort is the
   * sort order, or possibly null if m_file_count is zero.
   */
  let m_file_count = 0;
  let m_file_sort = null;
  
  /*
   * Local functions
   * ===============
   */
  
  /*
   * Remove everything that is displayed in the file table and reset
   * m_file_count back to zero and m_file_sort back to null.
   */
  function clearFileDisplay() {
    // Get the table body element
    const tblData = findElement("tblData");
    
    // Remove all child elements from the table data element to clear it
    while (tblData.lastChild) {
      tblData.removeChild(tblData.lastChild);
    }
    
    // Reset data state
    m_file_count = 0;
    m_file_sort = null;
  }
  
  /*
   * Release m_node back to null.
   * 
   * This makes sure to call close() on it before releasing so that any
   * URLs are cleaned up.
   */
  function releaseNodeCache() {
    if (m_node !== null) {
      m_node.close();
      m_node = null;
    }
  }
  
  /*
   * Check whether the given parameter is a finite integer.
   * 
   * Parameters:
   * 
   *   i - the value to check
   * 
   * Return:
   * 
   *   true if finite integer, false if not
   */
  function isInteger(i) {
    if (typeof(i) !== "number") {
      return false;
    }
    if (!isFinite(i)) {
      return false;
    }
    if (Math.floor(i) !== i) {
      return false;
    }
    return true;
  }
  
  /*
   * Escape the < > & characters in a string with HTML entities so that
   * the string can be used as HTML code.
   * 
   * Parameters:
   * 
   *   str : string - the string to escape
   * 
   * Return:
   * 
   *   the escaped string
   */
  function escapeHTML(str) {
    // Check parameter
    if (typeof(str) !== "string") {
      throw new TypeError();
    }
    
    // Replace the control characters, ampersand first
    str = str.replace(/&/g, "&amp;");
    str = str.replace(/</g, "&lt;" );
    str = str.replace(/>/g, "&gt;" );
    
    // Return replaced string
    return str;
  }
  
  /*
   * Get a document element with the given ID.
   * 
   * An exception is thrown if no element with that ID is found.
   * 
   * Parameters:
   * 
   *   eid : string - the ID of the element
   * 
   * Return:
   * 
   *   the element
   */
  function findElement(eid) {
    // Check parameter
    if (typeof(eid) !== "string") {
      throw new TypeError();
    }
    
    // Query for element
    const e = document.getElementById(eid);
    if (!e) {
      throw new Error("Can't find element with ID '" + eid + "'");
    }
    
    // Return the element
    return e;
  }
  
  /*
   * Hide all main DIVs and then show the DIV with the given ID.
   * 
   * The given ID must be one of the DIVs in the DIV_LIST constant.
   * 
   * Parameters:
   * 
   *   divid : string - the ID of the main DIV to show
   */
  function showDIV(divid) {
    
    // Check parameter
    if (typeof(divid) !== "string") {
      throw new TypeError();
    }
    
    // Check that ID is recognized
    let found = false;
    for(let i = 0; i < DIV_LIST.length; i++) {
      if (DIV_LIST[i] === divid) {
        found = true;
        break;
      }
    }
    if (!found) {
      throw new Error("Invalid DIV ID");
    }
    
    // Hide all top-level DIVs
    for(let i = 0; i < DIV_LIST.length; i++) {
      findElement(DIV_LIST[i]).style.display = "none";
    }
    
    // Show the desired DIV
    findElement(divid).style.display = "block";
  }
  
  /*
   * Show the load error DIV with a given message.
   * 
   * The message should NOT be HTML escaped.
   * 
   * Parameters:
   * 
   *   msg : string - the loading error message to show
   */
  function showLoadError(msg) {
    // Check parameter
    if (typeof(msg) !== "string") {
      throw new TypeError();
    }
    
    // Update the message content
    findElement("divMessageContent").innerHTML = escapeHTML(msg);
    
    // Show the error message DIV
    showDIV("divLoadError");
  }
  
  /*
   * Clear the main view's trail display and update it to match the
   * trail in m_node.
   * 
   * m_node must be defined and loaded.
   */
  function writeTrail() {
    // Check state
    if (m_node === null) {
      throw new Error("Invalid state");
    }
    if (!m_node.isLoaded()) {
      throw new Error("Invalid state");
    }
    
    // Get the trail element
    const divTrail = findElement("divTrail");
    
    // Remove all child elements from the trail to clear it
    while (divTrail.lastChild) {
      divTrail.removeChild(divTrail.lastChild);
    }
    
    // Create elements representing each of the trail components
    const comps = [];
    for(let i = 0; i < m_node.trailCount(); i++) {
      // Get the trail component
      const tc = m_node.trailItem(i);
      
      // Create a span for the last trail component and an anchor for
      // everything else
      let e = null;
      if (i === m_node.trailCount() - 1) {
        // Last element, create a span
        e = document.createElement("span");
        
        // Add the "trailhere" CSS class to the span
        e.classList.add("trailhere");
        
      } else {
        // Not last element, create an anchor
        e = document.createElement("a");
        
        // Add a JavaScript URL that will go to the requested directory
        e.href = "javascript:void(speakeasy.goDir(" +
                  tc.objectID.toString(10) +
                  "));"
      }
      
      // Create the text of the node, which equals the directory name
      let te = document.createTextNode(tc.dirName);
      
      // Add the text node as a child to the main trail node
      e.appendChild(te);
      
      // Add the finished trail component node to the array
      comps.push(e);
    }
    
    // Insert each of the trail component elements as children of the
    // trail element, but prefix a text node " / " prior to each trail
    // component after the first
    for(let i = 0; i < comps.length; i++) {
      if (i > 0) {
        divTrail.appendChild(document.createTextNode(" / "));
      }
      divTrail.appendChild(comps[i]);
    }
  }
  
  /*
   * Clear the main view's folder display and update it to match the.
   * folders in m_node.
   * 
   * m_node must be defined and loaded.
   */
  function writeFolders() {
    // Check state
    if (m_node === null) {
      throw new Error("Invalid state");
    }
    if (!m_node.isLoaded()) {
      throw new Error("Invalid state");
    }
    
    // Get the subfolders element
    const divFolders = findElement("divSubfolders");
    
    // Remove all child elements from the subfolders element to clear it
    while (divFolders.lastChild) {
      divFolders.removeChild(divFolders.lastChild);
    }
    
    // The main element is a <ul> list, unless there are no subfolders,
    // in which case the main element is a text node saying
    // "No subfolders"
    let main = null;
    if (m_node.folderCount() < 1) {
      // No folders
      main = document.createTextNode("No subfolders");
      
    } else {
      // At least one folder
      main = document.createElement("ul");
    }
    
    // Add any folders as child <li> elements
    for(let i = 0; i < m_node.folderCount(); i++) {
      // Get folder
      const folderItem = m_node.folderItem(i);
      
      // Create the new <li> node
      const n = document.createElement("li");
      
      // Create the <a> element
      const a = document.createElement("a");
      
      // Set the appropriate JavaScript link for the folder
      a.href = "javascript:void(speakeasy.goDir(" +
                  folderItem.objectID.toString(10) + "));"
      
      // Add the folder name as a text node under the anchor
      a.appendChild(document.createTextNode(folderItem.dirName));
      
      // Add the anchor as a child of the <li> node and then append the
      // <li> node to the main node
      n.appendChild(a);
      main.appendChild(n);
    }
    
    // Add the main node to the folder display
    divFolders.appendChild(main);
  }
  
  /*
   * Update the files displayed in the tables.
   * 
   * This uses m_file_count and m_file_sort to determine what is
   * currently being displayed in the table and in what sorting order,
   * so that it only adds new entries.
   * 
   * New rows will be added if any new files are available in m_node,
   * which must be defined and loaded.  If the sorting order has
   * changed, the table is cleared and completely rebuilt.
   * 
   * This also updates the divShowMore visibility appropriately.
   */
  function writeFiles() {
    // Check state
    if (m_node === null) {
      throw new Error("Invalid state");
    }
    if (!m_node.isLoaded()) {
      throw new Error("Invalid state");
    }
    
    // If sort order has changed, then we need to clear display
    if (m_file_count > 0) {
      if (m_file_sort !== m_node.getSortType()) {
        clearFileDisplay();
      }
    }
    
    // Add any new file entries
    for(let i = m_file_count; i < m_node.fileCount(); i++) {
      // Get the file entry
      const fil = m_node.fileItem(i);
      
      // Create the new <tr> node
      const tr = document.createElement("tr");
      
      // Create the pic and entry <td> elements
      const tdPic = document.createElement("td");
      tdPic.classList.add("pic");
      
      const tdEntry = document.createElement("td");
      tdEntry.classList.add("entry");
      
      // Create an <img> for the thumbnail and
      const img = document.createElement("img");
      img.src = fil.thumbURL;
      
      // Wrap the <img> in an <a> that opens image in separate tab
      const aimg = document.createElement("a");
      aimg.href = fil.dataURL;
      aimg.target = "_blank";
      aimg.appendChild(img);
      
      // Add the linked img to the pic cell
      tdPic.appendChild(aimg);
      
      // Add the text content to the entry node
      tdEntry.appendChild(document.createTextNode(fil.fileName));
      tdEntry.appendChild(document.createElement("br"));
      tdEntry.appendChild(document.createTextNode(fil.fileTime));
      if (fil.fileDesc.length > 0) {
        tdEntry.appendChild(document.createElement("br"));
        tdEntry.appendChild(document.createElement("br"));
        tdEntry.appendChild(document.createTextNode(fil.fileDesc));
      }
      
      // Add each <td> element into the row
      tr.appendChild(tdPic);
      tr.appendChild(tdEntry);
      
      // Append the row to the body
      tblData.appendChild(tr);
    }
    
    // Update file display information
    m_file_count = m_node.fileCount();
    m_file_sort = m_node.getSortType();
    
    // Update visibility of show more button
    if (m_node.hasAllFiles()) {
      findElement("divShowMore").style.display = "none";
    } else {
      findElement("divShowMore").style.display = "block";
    }
  }
  
  /*
   * Display the given directory ID.
   * 
   * m_data must be loaded for this to work, and m_node must be defined.
   * 
   * Parameters:
   * 
   *   dirid : integer - the directory ID to show
   */
  async function loadDisplay(dirid) {
    // Check parameter
    if (!isInteger(dirid)) {
      throw new TypeError();
    }
    
    // Check state
    if (m_data === null) {
      throw new Error("No data file loaded");
    }
    if (m_node === null) {
      throw new Error("Node decoder not defined");
    }
    
    // Clear anything in the file display
    clearFileDisplay();
    
    // Load the node state
    await m_node.load(dirid);
    
    // Do initial file load
    await m_node.loadFiles(findElement("selSort").value, INITIAL_FILES);
    
    // Write the trail and folders
    writeTrail();
    writeFolders();
    
    // Write the loaded files
    writeFiles();
    
    // Show the directory display
    showDIV("divMain");
  }
  
  /*
   * Asynchronous function handler used when user chooses to load a new
   * file.
   * 
   * The only thing that has been done so far is to change the display
   * to the "Loading..." DIV and get the file from the display.
   * 
   * Exceptions may be thrown if any failure.  The main handler should
   * handle these exceptions properly.
   * 
   * Parameters:
   * 
   *   fil : File - the file to upload
   */
  async function uploadFile(fil) {
    // Check parameter
    if (!(fil instanceof File)) {
      throw new TypeError();
    }

    // Start a new Scavenger decoder
    m_data = new Scavenger();
    
    // Load the file in the decoder
    await m_data.load(fil);
    
    // Define a node reader on the decoder
    m_node = new SpeakEasyNode(m_data, ["image"]);
    
    // Finally, load the root directory
    await loadDisplay(0);
  }
  
  /*
   * Public functions
   * ================
   */

  /*
   * Invoked when the user decides to load more files.
   */
  function loadMore() {
    // Only do something if node loaded
    if ((m_node !== null) && (m_node.isLoaded())) {
      // Only do something if not all files loaded
      if (!m_node.hasAllFiles()) {
        // Asynchronously load more files in the current sort order
        (m_node.loadFiles(
            findElement("selSort").value, MORE_FILES)).then(
          (value) => {
            // File load operation completed, so now update the display
            // if node still defined and loaded
            if ((m_node !== null) && (m_node.isLoaded())) {
              writeFiles();
            }
          }
        );
      }
    }
  }

  /*
   * Invoked from dynamically generated listings to go to another
   * directory.
   * 
   * Parameters:
   * 
   *   dirid : integer - the directory to go to
   */
  function goDir(dirid) {
    // Check parameter
    if (!isInteger(dirid)) {
      throw new TypeError();
    }
    
    // Switch to loading screen
    showDIV("divLoading");
    
    // Load the new directory
    loadDisplay(dirid).catch(function(reason) {
      console.log(reason);
      showLoadError(reason.toString());
    });
  }

  /*
   * Invoked when we choose to reload a new SpeakEasy file.
   */
  function handleReload() {
    m_data = null;
    releaseNodeCache();
    showDIV("divLoadDialog");
    clearFileDisplay();
  }

  /*
   * Invoked when the user chooses to load a new file.
   */
  function handleUpload() {
    // First of all, switch to the loading screen and clear the data
    // state
    showDIV("divLoading");
    m_data = null;
    releaseNodeCache();
    clearFileDisplay();
    
    // Get the file control
    const eFile = document.getElementById("filUpload");
    if (!eFile) {
      throw new Error("Can't find element filUpload");
    }
    
    // Check that the user selected exactly one file; if not, then go to
    // load error dialog with appropriate message and do nothing further
    if (eFile.files.length !== 1) {
      showLoadError("Choose a file to view!");
      return;
    }
    
    // Call into our asynchronous loading function with the selected
    // file, and catch and report exceptions
    uploadFile(eFile.files.item(0)).catch(function(reason) {
      console.log(reason);
      showLoadError(reason.toString());
    });
  }

  /*
   * For the main load function, show the load dialog and add an event
   * handler to the sort order control.
   */
  function handleLoad() {
    // Add an event handler for sort order control
    const selSort = findElement("selSort");
    selSort.addEventListener('change', (ev) => {
      // Only do something if node loaded
      if ((m_node !== null) && (m_node.isLoaded())) {
        // Only do something if sort order has actually changed
        if (selSort.value !== m_node.getSortType()) {
          // Asynchronously perform a reload in the new sort order
          (m_node.loadFiles(selSort.value, INITIAL_FILES)).then(
            (value) => {
              // Sort operation completed, so now update the display if
              // node still defined and loaded
              if ((m_node !== null) && (m_node.isLoaded())) {
                writeFiles();
              }
            }
          );
        }
      }
    });
    
    // Show load dialog
    showDIV("divLoadDialog");
  }
  
  /*
   * Export declarations
   * ===================
   * 
   * All exports are declared within a global "speakeasy" object.
   */
  
  window.speakeasy = {
    "loadMore": loadMore,
    "goDir": goDir,
    "handleReload": handleReload,
    "handleUpload": handleUpload,
    "handleLoad": handleLoad
  };

}());

// Call into our load handler once DOM is ready
document.addEventListener('DOMContentLoaded', speakeasy.handleLoad);
