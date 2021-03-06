#               OpenCenter™ is Copyright 2013 by Rackspace US, Inc.
# ###############################################################################
#
# OpenCenter is licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.  This version
# of OpenCenter includes Rackspace trademarks and logos, and in accordance with
# Section 6 of the License, the provision of commercial support services in
# conjunction with a version of OpenCenter which includes Rackspace trademarks
# and logos is prohibited.  OpenCenter source code and details are available at:
# https://github.com/rcbops/opencenter or upon written request.
#
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this notice,
# is available in the LICENSE file accompanying this software.
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# ###############################################################################

# Define Array::filter if not using ECMA5
unless Array::filter
  Array::filter = (cb) ->
    el for el in @ when cb el

# Create and store namespace
dashboard = exports?.dashboard ? @dashboard = {}

dashboard.selector = (cb, def) ->
  selected = ko.observable def ? {} unless selected?
  cb def if cb? and def?
  ko.computed
    read: ->
      selected()
    write: (data) ->
      selected data
      cb data if cb?

# Object -> Array mapper
dashboard.toArray = (obj) ->
  array = []
  for prop of obj
    if obj.hasOwnProperty(prop)
      array.push
        key: prop
        value: obj[prop]

  array # Return mapped array

dashboard.getPopoverPlacement = (tip, element) ->
  isWithinBounds = (elementPosition) ->
    boundTop < elementPosition.top and boundLeft < elementPosition.left and boundRight > (elementPosition.left + actualWidth) and boundBottom > (elementPosition.top + actualHeight)
  $element = $ element
  pos = $.extend {}, $element.offset(),
    width: element.offsetWidth
    height: element.offsetHeight
  actualWidth = 283
  actualHeight = 117
  boundTop = $(document).scrollTop()
  boundLeft = $(document).scrollLeft()
  boundRight = boundLeft + $(window).width()
  boundBottom = boundTop + $(window).height()
  elementAbove =
    top: pos.top - actualHeight
    left: pos.left + pos.width / 2 - actualWidth / 2

  elementBelow =
    top: pos.top + pos.height
    left: pos.left + pos.width / 2 - actualWidth / 2

  elementLeft =
    top: pos.top + pos.height / 2 - actualHeight / 2
    left: pos.left - actualWidth

  elementRight =
    top: pos.top + pos.height / 2 - actualHeight / 2
    left: pos.left + pos.width

  above = isWithinBounds elementAbove
  below = isWithinBounds elementBelow
  left = isWithinBounds elementLeft
  right = isWithinBounds elementRight
  (if above then "top" else (if below then "bottom" else (if left then "left" else (if right then "right" else "right"))))

# Keep track of AJAX success/failure
dashboard.siteEnabled = ko.observable true
dashboard.siteDisable = -> dashboard.siteEnabled false
dashboard.siteEnable = -> dashboard.siteEnabled true

# Toggle task/log pane
dashboard.displayTaskLogPane = ko.observable false

# Fill in auth header with user/pass
dashboard.makeBasicAuth = (user, pass) ->
  dashboard.authUser user
  token = "#{user}:#{pass}"
  dashboard.authHeader = Authorization: "Basic #{btoa token}"

# Auth bits
dashboard.authHeader = {}
dashboard.authUser = ko.observable ""
dashboard.authCheck = ko.computed ->
  if dashboard.authUser() isnt "" then true else false
dashboard.authLogout = ->
  # Clear out all the things
  model = dashboard.indexModel
  dashboard.authHeader = {}
  dashboard.authUser ""
  model.keyItems = {}
  model.tmpItems []
  # Try grabbing new nodes; will trigger login form if needed
  dashboard.getNodes "/octr/nodes/", model.tmpItems, model.keyItems

# Guard to spin requests while logging in
dashboard.loggingIn = false

dashboard.drawStepProgress = ->
  $form = $("form#inputForm")
  $multiStepForm = $form.find(".carousel")
  $formBody = $form.find(".modal-body")
  $formControls = $form.find(".modal-footer")

  if $multiStepForm.length and $formControls.length
    $back = $formControls.find(".back")
    $next = $formControls.find(".next")
    $submit = $formControls.find(".submit")
    slideCount = $multiStepForm.find('.carousel-inner .item').length

    if slideCount is 1
      $back.hide()
      $next.hide()
      $submit.show()
    else
      str = ""
      count = 0
      percentWidth = 100 / slideCount

      while count < slideCount
        str += "<div id=\"progress-bar-" + (count + 1) + "\" class=\"progress-bar\" style=\"width:" + percentWidth + "%;\"></div>"
        count++

      $progressMeter = $("#progress-meter")
      $progressMeter.remove()  if $progressMeter.length
      $progressMeter = $('<div id="progress-meter">' + str + '</div>').prependTo($formBody)
      $back.attr "disabled", true
      $submit.hide()

    $multiStepForm.on "slid", "", ->
      $this = $(this)
      $progressMeter.find(".progress-bar").removeClass "filled"
      $activeProgressBars = $progressMeter.find('.progress-bar').slice 0, parseInt $(".carousel-inner .item.active").index() + 1, 10
      $activeProgressBars.addClass "filled"
      $formControls.find("button").show().removeAttr "disabled"
      if $this.find(".carousel-inner .item:first").hasClass("active")
        $back.attr "disabled", true
        $submit.hide()
      else if $this.find(".carousel-inner .item:last").hasClass("active")
        $next.hide()
        $submit.show()
      else
        $submit.hide()

# Modal helpers
dashboard.showModal = (id) ->
  $(".modal").not(id).modal "hide"
  dashboard.drawStepProgress() if id is '#indexInputModal'
  $(id).modal("show").on "shown", ->
    $(id).find("input").first().focus()
dashboard.hideModal = (id) ->
  $(id).modal "hide"

# Track AJAX requests keyed by URL
dashboard.pendingRequests = {}

# Kill requests by regex matching url
dashboard.killRequests = (match) ->
  for k,v of dashboard.pendingRequests
    if match.test k
      v.abort()

# AJAX wrapper which auto-retries on error
dashboard.ajax = (type, url, data, success, error, timeout, statusCode) ->
  req = ->
    if dashboard.loggingIn # If logging in
      setTimeout req, 1000 # Spin request
    else
      dashboard.pendingRequests[url] = $.ajax # Call and store request
        type: type
        url: url
        data: data
        headers: dashboard.authHeader # Add basic auth
        success: (data) ->
          dashboard.siteEnable() # Enable site
          dashboard.hideModal "#indexNoConnectionModal" # Hide immediately
          req.backoff = 250 # Reset on success
          success data if success?
        error: (jqXHR, textStatus, errorThrown) ->
          retry = error jqXHR, textStatus, errorThrown if error?
          if jqXHR.status is 401 # Unauthorized!
            dashboard.loggingIn = true # Block other requests
            dashboard.showModal "#indexLoginModal" # Gimmeh logins
            setTimeout req, 1000 # Requeue this one
          else if retry is true and type is "GET" # Opted in and not a POST
            setTimeout req, req.backoff # Retry with incremental backoff
            unless jqXHR.status is 0 # Didn't timeout
              dashboard.siteDisable() # Don't disable on repolls and such
              req.backoff *= 2 if req.backoff < 32000 # Do eet
        complete: -> delete dashboard.pendingRequests[url] # Clean up our request
        statusCode: statusCode
        dataType: "json"
        contentType: "application/json; charset=utf-8"
        timeout: timeout
  req.backoff = 250 # Start at 0.25 sec
  req()

# Request wrappers
dashboard.get = (url, success, error, timeout, statusCode) ->
  dashboard.ajax "GET", url, null, success, error, timeout, statusCode

dashboard.post = (url, data, success, error, timeout, statusCode) ->
  dashboard.ajax "POST", url, data, success, error, timeout, statusCode

# Basic JS/JSON grabber
dashboard.getData = (url, cb, err) ->
  dashboard.get url, (data) ->
    cb data if cb?
  , err ? -> true # Retry

# Use the mapping plugin on a JS object, optional mapping mapping (yo dawg), wrap for array
dashboard.mapData = (data, pin, map={}, wrap=true) ->
  data = [data] if wrap
  ko.mapping.fromJS data, map, pin

# Get and map data, f'reals
dashboard.getMappedData = (url, pin, map={}, wrap=true) ->
  dashboard.get url, (data) ->
    dashboard.mapData data, pin, map, wrap
  , -> true # Retry

# Parse node array into a flat, keyed boject, injecting children for traversal
dashboard.parseNodes = (data, keyed={}) ->
  root = {} # We might not find a root; make sure it's empty each call

  # Index node list by ID, merging/updating if keyed was provided
  for node in data?.nodes ? []
    # Stub if missing
    node.dash ?= {}
    node.dash.actions ?= []
    node.dash.statusClass ?= ko.observable "disabled_state"
    node.dash.statusText ?= ko.observable "Unknown"
    node.dash.locked ?= ko.observable false
    node.dash.children ?= {}
    node.dash.hovered ?= keyed[nid]?.dash.hovered ? false
    node.facts ?= {}
    node.facts.backends ?= []

    nid = node.id
    if keyed[nid]? # Updating existing node?
      pid = keyed[nid].facts?.parent_id # Grab current parent
      if pid? and pid isnt node.facts?.parent_id # If new parent is different
        dashboard.killPopovers() # We're moving so kill popovers
        keyed[nid].dash.hovered = false # And cancel hovers
        delete keyed[pid].dash.children[nid] # Remove node from old parent's children

    keyed[nid] = node # Add/update node

  # Build child arrays
  for id of keyed
    node = keyed[id]
    pid = node.facts?.parent_id
    if pid? # Has parent ID?
      pnode = keyed?[pid]
      if pnode? # Parent exists?
        pnode.dash.children[id] = node # Add to parent's children
      else # We're an orphan (broken data or from previous merge)
        delete keyed[id] # No mercy for orphans!
    else if id is "1" # Mebbe root node?
      root = node # Point at it
    else # Invalid root node!
      delete keyed[id] # Pew Pew!

  # Node staleness checker
  stale = (node) ->
    if node?.attrs?.last_checkin? # Have we checked in at all?
      if Math.abs(+node.attrs.last_checkin - +dashboard.txID) > 90 then true # Hasn't checked in for 3 cycles
      else false
    else false

  # Fill other properties
  for id of keyed
    node = keyed[id]
    if node?.attrs?.last_task is "failed"
      dashboard.setError node
    else if stale(node) or node?.attrs?.last_task is "rollback"
      dashboard.setWarning node
    else if node.task_id?
      dashboard.setBusy node
    else if node.facts.maintenance_mode
      dashboard.setDisabled node
    else
      dashboard.setGood node

    if node.dash.hovered
      dashboard.updatePopover $("[data-bind~='popper'],[data-id='#{id}']"), node, true # Update matching popover

    # If we have a non-empty display name, set the name to it
    if node?.attrs?.display_name? and !!node.attrs.display_name
      node.name = node.attrs.display_name

    node.dash.agents = (v for k,v of node.dash.children when "agent" in v.facts.backends)
    node.dash.containers = (v for k,v of node.dash.children when "container" in v.facts.backends)

    if node?.attrs?.locked # Node is locked
      node.dash.locked true

  root # Return root for mapping

dashboard.setError = (node) ->
  node.dash.statusClass "error_state"
  node.dash.statusText "Error"
  node.dash.locked false

dashboard.setWarning = (node) ->
  node.dash.statusClass "processing_state"
  node.dash.statusText "Warning"
  node.dash.locked false

dashboard.setBusy = (node) ->
  node.dash.statusClass "warning_state"
  node.dash.statusText "Busy"
  node.dash.locked true

dashboard.setGood = (node) ->
  node.dash.statusClass "ok_state"
  node.dash.statusText "Good"
  node.dash.locked false

dashboard.setDisabled = (node) ->
  node.dash.statusClass "disabled_state"
  node.dash.statusText "Disabled"

# Process nodes and map to pin
dashboard.updateNodes = (data, pin, keys) ->
  dashboard.mapData dashboard.parseNodes(data, keys), pin

# Get and process nodes from url
dashboard.getNodes = (url, pin, keys) ->
  dashboard.get url, (data) ->
    dashboard.updateNodes data, pin, keys
  , -> true # Retry

# Long-poll for node changes and do the right things on changes
dashboard.pollNodes = (cb, timeout) ->
  repoll = (trans) ->
    if trans? # Have transaction data?
      dashboard.sKey = trans.session_key
      dashboard.txID = trans.txid
      poll "/octr/nodes/updates/#{dashboard.sKey}/#{dashboard.txID}?poll" # Build URL
    else # Get you some
      dashboard.getData "/octr/updates", (pass) ->
        repoll pass?.transaction # Push it back through

  poll = (url) ->
    dashboard.get url
    , (data) -> # Success
        cb data?.nodes if cb?
        repoll data?.transaction
    , (jqXHR, textStatus, errorThrown) -> # Error; can retry after this cb
        switch jqXHR.status
          when 410 # Gone
            repoll() # Cycle transaction
            dashboard.getNodes "/octr/nodes/", dashboard.indexModel.tmpItems, dashboard.indexModel.keyItems
          else
            true # Retry otherwise
    , timeout

  repoll() # DO EET

# Just map the tasks
dashboard.updateTasks = (data, pin, keys) ->
  dashboard.mapData dashboard.parseTasks(data, keys), pin, {}, false # Don't wrap

# Get and process tasks from url
dashboard.getTasks = (url, pin, keys) ->
  dashboard.get url, (data) ->
    dashboard.updateTasks data, pin, keys
  #, -> true # Retry

# Dumb polling for now
dashboard.pollTasks = (cb, timeout) ->
  poll = (url) ->
    dashboard.get url
    , (data) -> # Success
      cb data if cb?
      setTimeout poll, timeout, url
    , (jqXHR, textStatus, errorThrown) ->
      true # Retry on failure
    , timeout
  poll "/octr/tasks/" # Do it

dashboard.parseTasks = (data, keyed) ->
  ids = [] # List of new IDs

  # Parse new tasks
  tasks = for task in data.tasks
    id = task.id # Grab
    ids.push id # Push
    unless task.action in ["logfile.tail", "logfile.watch"]  # Don't show log tasks
      task.dash = {} # Stub our config storage
      switch task.state
        when "pending","delivered","running"
          task.dash.statusClass = "warning_state" # Busy
        when "timeout"
          task.dash.statusClass = "processing_state" # Warning
        when "cancelled"
          task.dash.statusClass = "error_state" # Error
        when "done"
          task.dash.statusClass = "ok_state" # Good

      if task?.result?.result_code # Non-zero result is bad
        task.dash.statusClass = "error_state" # Error

      if keyed[id]? # Updating existing task?
        task.dash.active = keyed[id].dash.active # Track selected status
      else task.dash.active = false

      task.dash.label = "#{task.id}: #{task.action} [#{task.state}]"

      if task.dash.active # If a task is selected
        dashboard.indexModel.wsTaskTitle task.dash.label # Update the title

      keyed[id] = task # Set and return it
    else continue # Skip it

  # So we can update logpane when the active task is reaped/none are selected
  activeCount = 0

  # Prune
  for k of keyed
    unless +k in ids # Coerce to int, lulz
      delete keyed[k] # Toss reaped tasks
    else
      activeCount++ # Got an active (selected) one!

  if !activeCount # If none were selected
    # Reset log pane bits
    dashboard.indexModel.wsTaskTitle "Select a task to view its log"
    dashboard.indexModel.wsTaskLog "..."

  tasks # Return list

dashboard.popoverOptions =
  html: true
  delay: 0
  trigger: "manual"
  animation: false
  placement: dashboard.getPopoverPlacement
  container: 'body'

dashboard.killPopovers = ->
  $("[data-bind~='popper']").popover "hide"
  $(".popover").remove()

dashboard.updatePopover = (el, obj, show=false) ->
  opts = dashboard.popoverOptions
  doIt = (task) ->
    opts["title"] =
      #TODO: Figure out why this fires twice: console.log "title"
      """
      #{obj.name ? "Details"}
      <ul class="backend-list tags">
          #{('<li><div class="item">' + backend + '</div></li>' for backend in obj.facts.backends).join('')}
      </ul>
      """
    opts["content"] =
      """
      <dl class="node-data">
        <dt>ID</dt>
        <dd>#{obj.id}</dd>
        <dt>Status</dt>
        <dd>#{obj.dash.statusText()}</dd>
        <dt>Task</dt>
        <dd>#{task ? 'idle'}</dd>
        <dt>Last Task</dt>
        <dd>#{obj?.attrs?.last_task ? 'unknown'}</dd>
      </dl>
      """
    $(el).popover opts
    if show
      dashboard.killPopovers()
      $(el).popover "show"

  if obj?.task_id?
    dashboard.get "/octr/tasks/#{obj.task_id}"
    , (data) -> doIt data?.task?.action
    , -> doIt()
  else
    doIt()

dashboard.convertValueType = (type) ->
  switch type
    when "password" then "password"
    else "text"
