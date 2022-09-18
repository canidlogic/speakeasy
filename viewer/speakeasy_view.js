"use strict";

/*
 * speakeasy_view.js
 * =================
 * 
 * JavaScript code for the SpeakEasy viewer app.
 * 
 * You must also load scavenger.js.
 */

// Wrap everything in an anonymous function that we immediately invoke
// after it is declared -- this prevents anything from being implicitly
// added to global scope
(function() {
  
  /*
   * FullScreen API wrapper
   * ======================
   */

  /*
   * _FULLSCREEN_ALIAS stores a mapping of standard fullscreen API names
   * to arrays that begin with the standard name and then have any
   * vendor prefix names.
   * 
   * Make sure that each array has prefixes in same order.  The function
   * _fullscreenchange() depends on this.
   */
  const _FULLSCREEN_ALIAS = {
    "fullscreenEnabled": [
      "fullscreenEnabled",
      "webkitFullscreenEnabled",
      "mozFullScreenEnabled",
      "msFullscreenEnabled"
    ],
    "fullscreenElement": [
      "fullscreenElement",
      "webkitFullscreenElement",
      "mozFullScreenElement",
      "msFullscreenElement"
    ],
    "exitFullscreen": [
      "exitFullscreen",
      "webkitExitFullscreen",
      "mozCancelFullScreen",
      "msExitFullscreen"
    ],
    "requestFullscreen": [
      "requestFullscreen",
      "webkitRequestFullscreen",
      "mozRequestFullScreen",
      "msRequestFullscreen"
    ],
    "fullscreenchange": [
      "fullscreenchange",
      "webkitfullscreenchange",
      "mozfullscreenchange",
      "msfullscreenchange"
    ]
  };
  
  /*
   * Read the document.fullscreenEnabled property and return its boolean
   * value, using vendor-specific prefixes if necessary.
   * 
   * If no suitable API function is found, this returns false,
   * simulating a response of full screen not available.
   */
  function _fullscreenEnabled() {
    var i, fa;
    
    // Look for an API function
    fa = _FULLSCREEN_ALIAS.fullscreenEnabled;
    for(i = 0; i < fa.length; i++) {
      if (fa[i] in document) {
        return document[fa[i]];
      }
    }
    
    // If we got here, no API function so just return false
    return false;
  };
  
  /*
   * Read the document.fullscreenElement property and return the Element
   * or null if nothing fullscreen, using vendor-specific prefixes if
   * necessary.
   * 
   * If no suitable API function is found, this returns null, simulating
   * a response of nothing is fullscreen.
   */
  function _fullscreenElement() {
    var i, fa;
    
    // Look for an API function
    fa = _FULLSCREEN_ALIAS.fullscreenElement;
    for(i = 0; i < fa.length; i++) {
      if (fa[i] in document) {
        return document[fa[i]];
      }
    }
    
    // If we got here, no API function so just return null
    return null;
  };
  
  /*
   * Call document.exitFullscreen() and return the Promise for exiting
   * the full screen state, using vendor-specific prefixes if necessary.
   * 
   * If no suitable API function is found, this returns a rejected
   * Promise, simulating a response of encountering an error while
   * leaving fullscreen.
   */
  function _exitFullscreen() {
    var i, fa;
    
    // Look for an API function
    fa = _FULLSCREEN_ALIAS.exitFullscreen;
    for(i = 0; i < fa.length; i++) {
      if (fa[i] in document) {
        return document[fa[i]]();
      }
    }
    
    // If we got here, no API function so just return rejected promise
    return Promise.reject("Fullscreen API not available");
  };
  
  /*
   * Call requestFullscreen() on the given element and return the
   * Promise for entering the full screen state, using vendor-specific
   * prefixes if necessary.
   * 
   * options is the options parameter that should be passed, or
   * undefined if no options parameter should be passed.
   * 
   * If no suitable API function is found, this returns a rejected
   * Promise, simulating a response of encountering an error while
   * leaving fullscreen.
   */
  function _requestFullscreen(e, options) {
    var i, fa;
    
    // Check that we got some kind of object
    if (typeof(e) !== "object") {
      throw new TypeError();
    }
    
    // Look for an API function
    fa = _FULLSCREEN_ALIAS.requestFullscreen;
    for(i = 0; i < fa.length; i++) {
      if (fa[i] in e) {
        if (options !== undefined) {
          return e[fa[i]](options);
        } else {
          return e[fa[i]]();
        }
      }
    }
    
    // If we got here, no API function so just return rejected promise
    return Promise.reject("Fullscreen API not available");
  };
  
  /*
   * Return the event name to use for the fullscreenchange event.
   */
  function _fullscreenchange() {
    var i, fa;
    
    // Check what prefix, if any, is needed for an API function
    fa = _FULLSCREEN_ALIAS.fullscreenEnabled;
    for(i = 0; i < fa.length; i++) {
      if (fa[i] in document) {
        // Index i in array is what we need to use
        return _FULLSCREEN_ALIAS.fullscreenchange[i];
      }
    }
    
    // If we got here, just return the standard name
    return _FULLSCREEN_ALIAS.fullscreenchange[0];
  };

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
   * When we are currently displaying a directory, this holds the cached
   * file display information.
   * 
   * The "files" property stores the parsed JSON files object.
   * 
   * The "urls" property stores a mapping from object IDs to data URLs
   * that are used to access those resources.
   * 
   * The "current_sort" stores the current sort_id that is being
   * displayed.
   * 
   * When no directory is being displayed, this is null.
   * 
   * Use releaseFileCache() to set this back to none, to ensure that all
   * the urls in the urls map get released.
   */
  let m_file_cache = null;
  
  /*
   * Flag that is set once a re-sort operation is scheduled to run soon.
   */
  let m_sort_scheduled = false;
  
  /*
   * Local functions
   * ===============
   */
  
  /*
   * Release m_file_cache back to null.
   * 
   * This makes sure any urls in the cache are released.
   */
  function releaseFileCache() {
    if (m_file_cache !== null) {
      const keys = Object.keys(m_file_cache.urls);
      for(let x = 0; x < keys.length; x++) {
        URL.revokeObjectURL(m_file_cache.urls[keys[x]]);
      }
      m_file_cache = null;
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
  function jsonInteger(i) {
    // If already an integer, return that
    if (isInteger(i)) {
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
    if (!isInteger(i)) {
      throw new Error("Unexpected");
    }
    
    // Return converted integer
    return i;
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
   * Given the parsed JSON trail array, clear the main view's trail
   * display and update it to match the given trail.
   * 
   * The parsed JSON trail array must be an array with at least one
   * element.  Each trail array element is a subarray with two elements.
   * The first is the directory ID as a JSON integer, the second is the
   * directory name as a string.
   * 
   * Parameters:
   * 
   *   trail : array - the parsed JSON trail to write to display
   */
  function writeTrail(trail) {
    // Check parameter
    if (!(trail instanceof Array)) {
      throw new TypeError();
    }
    
    if (trail.length < 1) {
      throw new TypeError();
    }
    
    for(let i = 0; i < trail.length; i++) {
      const a = trail[i];
      
      if (!(a instanceof Array)) {
        throw new TypeError();
      }
      if (a.length !== 2) {
        throw new TypeError();
      }
      
      const x = a[0];
      const y = a[1];
      
      if ((jsonInteger(x) === null) ||
          (typeof(y) !== "string")) {
        throw new TypeError();
      }
    }
    
    // Get the trail element
    const divTrail = findElement("divTrail");
    
    // Remove all child elements from the trail to clear it
    while (divTrail.lastChild) {
      divTrail.removeChild(divTrail.lastChild);
    }
    
    // Create elements representing each of the trail components
    const comps = [];
    for(let i = 0; i < trail.length; i++) {
      // Create a span for the last trail component and an anchor for
      // everything else
      let e = null;
      if (i === trail.length - 1) {
        // Last element, create a span
        e = document.createElement("span");
        
        // Add the "trailhere" CSS class to the span
        e.classList.add("trailhere");
        
      } else {
        // Not last element, create an anchor
        e = document.createElement("a");
        
        // Add a JavaScript URL that will go to the requested directory
        e.href = "javascript:void(speakeasy.goDir(" +
                  jsonInteger(trail[i][0]).toString(10) +
                  "));"
      }
      
      // Create the text of the node, which equals the directory name
      let te = document.createTextNode(trail[i][1]);
      
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
   * Given the parsed JSON folders array, clear the main view's folder
   * display and update it to match the given folders object.
   * 
   * The parsed JSON array has subarrays of two elements, the first
   * being a directory ID and the second being the name of the
   * directory.  The entries are not in any particular order.
   * 
   * Parameters:
   * 
   *   folders : object - the parsed JSON folders array to write to
   *   display
   */
  function writeFolders(folders) {
    // Check parameter
    if (!(folders instanceof Array)) {
      throw new TypeError();
    }
    
    // Check all values
    for(let i = 0; i < folders.length; i++) {
      const a = folders[i];
      
      if (!(a instanceof Array)) {
        throw new TypeError();
      }
      if (a.length !== 2) {
        throw new TypeError();
      }
      
      const x = a[0];
      const y = a[1];
      
      if ((jsonInteger(x) === null) || (typeof(y) !== "string")) {
        throw new TypeError();
      }
    }
    
    // Sort the folder names according to the runtime default collation,
    // but with numeric collation enabled so that 1 < 2 < 10
    if (folders.length > 1) {
      const col = new Intl.Collator(undefined, {
        "numeric": true
      });
      folders.sort((a, b) => col.compare(a[1], b[1]));
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
    if (folders.length < 1) {
      // No folders
      main = document.createTextNode("No subfolders");
      
    } else {
      // At least one folder
      main = document.createElement("ul");
    }
    
    // Add any folders as child <li> elements
    for(let i = 0; i < folders.length; i++) {
      // Get the name and ID
      const folderName = folders[i][1];
      const folderID = jsonInteger(folders[i][0]);
      
      // Create the new <li> node
      const n = document.createElement("li");
      
      // Create the <a> element
      const a = document.createElement("a");
      
      // Set the appropriate JavaScript link for the folder
      a.href = "javascript:void(speakeasy.goDir(" +
                  folderID.toString(10) + "));"
      
      // Add the folder name as a text node under the anchor
      a.appendChild(document.createTextNode(folderName));
      
      // Add the anchor as a child of the <li> node and then append the
      // <li> node to the main node
      n.appendChild(a);
      main.appendChild(n);
    }
    
    // Add the main node to the folder display
    divFolders.appendChild(main);
  }
  
  /*
   * Given the parsed JSON files object, clear the main view's file
   * table body rows and update it to match the given files object,
   * according to the sorting selected by the sort control.
   * 
   * The parsed JSON files array contains the file objects in no
   * particular order.
   * 
   * You must also provide the mapping of object IDs to object URLs.
   * 
   * Parameters:
   * 
   *   files : array - the parsed JSON files array to write to display
   * 
   *   urls : object - the mapping of object IDs to object URLs
   */
  function writeFiles(files, urls) {
    // Check parameter
    if (!(files instanceof Array)) {
      throw new TypeError();
    }
    if (typeof(urls) !== "object") {
      throw new TypeError();
    }
    
    // Get the sort type and direction
    const sort_id = findElement("selSort").value;
    if (!((/^[a-z]+_[a-z]+$/).test(sort_id))) {
      throw new Error("Invalid sort_id " + sort_id);
    }
    const sort_parse = sort_id.split(/_/);
    if (sort_parse.length !== 2) {
      throw new Error("Unexpected");
    }
    
    const sort_type = sort_parse[0];
    const sort_dir  = sort_parse[1];
    
    // Sort the files in the selected order
    const col = new Intl.Collator(undefined, {
      "numeric": true
    });
    
    if (sort_type === "name") {
      files.sort((a, b) => col.compare(a.rname, b.rname));
      
    } else if (sort_type === "date") {
      files.sort((a, b) => col.compare(a.rtime, b.rtime));
      
    } else {
      throw new Error("Unsupported sort type " + sort_type);
    }
    
    // Depending on sort direction, we may need to reverse the order of
    // the keys array to get the final listing order
    if (sort_dir === "asc") {
      // Ascending, so do nothing we are in right order
      
    } else if (sort_dir === "desc") {
      // Descending, so reverse order
      files.reverse();
      
    } else {
      throw new Error("Unsupported sort_dir " + sort_dir);
    }
    
    // Get the table body element
    const tblData = findElement("tblData");
    
    // Remove all child elements from the table data element to clear it
    while (tblData.lastChild) {
      tblData.removeChild(tblData.lastChild);
    }
    
    // Add any file records as child <tr> elements; we only support
    // "image" class at the moment
    for(let i = 0; i < files.length; i++) {
      // Skip unless an image entry
      if (files[i].rclass !== "image") {
        continue;
      }
      
      // Get the name and date
      const fileName = files[i].rname;
      const fileDate = files[i].rtime;
      
      // Get description if available, else empty string
      let desc = "";
      if ("desc" in files[i]) {
        desc = files[i].desc;
      }
      
      // Create the new <tr> node
      const tr = document.createElement("tr");
      
      // Create the pic and entry <td> elements
      const tdPic = document.createElement("td");
      tdPic.classList.add("pic");
      
      const tdEntry = document.createElement("td");
      tdEntry.classList.add("entry");
      
      // Create an <img> for the thumbnail and
      const img = document.createElement("img");
      img.src = urls[files[i].tbin.toString(10)];
      
      // Wrap the <img> in an <a> that performs an enlarge
      const aimg = document.createElement("a");
      aimg.href = "javascript:void(speakeasy.showPic(" +
                    files[i].rbin.toString(10) + "));";
      aimg.appendChild(img);
      
      // Add the linked img to the pic cell
      tdPic.appendChild(aimg);
      
      // Add the text content to the entry node
      tdEntry.appendChild(document.createTextNode(fileName));
      tdEntry.appendChild(document.createElement("br"));
      tdEntry.appendChild(document.createTextNode(fileDate));
      if (desc.length > 0) {
        tdEntry.appendChild(document.createElement("br"));
        tdEntry.appendChild(document.createElement("br"));
        tdEntry.appendChild(document.createTextNode(desc));
      }
      
      // Add each <td> element into the row
      tr.appendChild(tdPic);
      tr.appendChild(tdEntry);
      
      // Append the row to the body
      tblData.appendChild(tr);
    }
  }
  
  /*
   * Display the given directory ID.
   * 
   * m_data must be loaded for this to work.
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
    
    // Check range of parameter
    if ((dirid < 0) || (dirid >= m_data.getCount())) {
      throw new Error("Directory ID out of range");
    }
    
    // Load the directory block
    let json = await m_data.fetchUTF8(dirid);
    json = JSON.parse(json);
    
    // Release anything currently in file cache
    releaseFileCache();
    
    // Go through all files and build the URLs map
    let urls = {};
    for(let x = 0; x < json.files.length; x++) {
      for(let y = 0; y < 2; y++) {
        // Get one of the two binary IDs and MIME types
        let binid;
        let binmime;
        
        if (y === 0) {
          binid = json.files[x].rbin;
          binmime = json.files[x].rmime;
          
        } else if (y === 1) {
          binid = json.files[x].tbin;
          binmime = json.files[x].tmime;
          
        } else {
          throw new Error("Unexpected");
        }
        
        // Skip if already defined
        if (binid.toString(10) in urls) {
          continue;
        }
        
        // Load blob
        const blob = await m_data.fetch(binid, binmime);
        
        // Add blob URL to map
        urls[binid.toString(10)] = URL.createObjectURL(blob);
      }
    }
    
    // Write the trail
    if (!("trail" in json)) {
      throw new Error("Missing trail");
    }
    writeTrail(json.trail);
    
    // Write the folders
    if (!("folders" in json)) {
      throw new Error("Missing folders");
    }
    writeFolders(json.folders);
    
    // Write the files
    if (!("files" in json)) {
      throw new Error("Missing files");
    }
    writeFiles(json.files, urls);
    
    // Set the file cache
    m_file_cache = {
      "files": json.files,
      "urls": urls,
      "current_sort": findElement("selSort").value
    };
    
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
    
    // Finally, load the root directory
    await loadDisplay(0);
  }
  
  /*
   * Public functions
   * ================
   */

  /*
   * Invoked when a picture is selected to show full-screen.
   * 
   * Parameters:
   * 
   *   objid : integer - the object ID of the full-size picture
   */
  function showPic(objid) {
    // Check parameter
    if (!isInteger(objid)) {
      throw new TypeError();
    }
    
    // Ignore if no file cache
    if (m_file_cache === null) {
      return;
    }
    
    // Ignore if object not cached
    if (!(objid.toString(10) in m_file_cache.urls)) {
      return;
    }
    
    // Get the URL of the full-size picture
    const url = m_file_cache.urls[objid.toString(10)];
    
    // Set the full-screen <img> for the URL
    findElement("imgFullPic").src = url;
    
    // Show the full DIV
    const div = findElement("divFullPic");
    div.style.display = "block";
    
    // Set image full-screen
    _requestFullscreen(div, { navigationUI: "hide" });
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
    releaseFileCache();
    showDIV("divLoadDialog");
  }

  /*
   * Invoked when the user chooses to load a new file.
   */
  function handleUpload() {
    // First of all, switch to the loading screen and clear the data
    // state
    showDIV("divLoading");
    m_data = null;
    releaseFileCache();
    
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
    // Add a click listener to the fullscreen <img> that revokes
    // fullscreen
    findElement("imgFullPic").addEventListener("click", function(ev) {
      _exitFullscreen();
      findElement("divFullPic").style.display = "none";
      findElement("imgFullPic").src = "";
    });
    
    // Add an event handler for sort order control
    const selSort = findElement("selSort");
    selSort.addEventListener('change', (ev) => {
      // Only do something if file cache loaded
      if (m_file_cache !== null) {
        // If sort has actually changed, then schedule a reload unless
        // already scheduled
        if (selSort.value !== m_file_cache.current_sort) {
          if (!m_sort_scheduled) {
            m_sort_scheduled = true;
            setTimeout(() => {
              
              // We are now a little bit later, so begin by clearing the
              // sort scheduling flag
              m_sort_scheduled = false;
              
              // If data and file cache both defined, then update the
              // current sort ID and write the new sorted contents
              if ((m_data !== null) && (m_file_cache !== null)) {
                m_file_cache.current_sort = selSort.value;
                writeFiles(m_file_cache.files, m_file_cache.urls);
              }
              
            }, 0);
          }
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
    "showPic": showPic,
    "goDir": goDir,
    "handleReload": handleReload,
    "handleUpload": handleUpload,
    "handleLoad": handleLoad
  };

}());

// Call into our load handler once DOM is ready
document.addEventListener('DOMContentLoaded', speakeasy.handleLoad);
