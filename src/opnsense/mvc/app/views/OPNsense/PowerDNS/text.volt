<style>
  #zoneTextEditor { font-family: monospace; min-height: 460px; white-space: pre; }
  .pdns-text-toolbar { margin-bottom: 10px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .pdns-text-toolbar .form-control { width: auto; min-width: 260px; }
  .pdns-text-help { color: #777; margin-top: 8px; }
</style>
<script>
var selectedTextZone = '';
function htmlEscape(s){ return $('<div/>').text(s === undefined || s === null ? '' : String(s)).html(); }
function showMessage(type, title, message) { BootstrapDialog.show({type: type, title: title, message: message}); }
function normalizeZoneName(zone){ return zone || $('#textZoneSelect').val() || selectedTextZone; }
function renderTextZoneOptions(data) {
  var options = '';
  (data || []).forEach(function(z){ options += '<option value="'+htmlEscape(z.name)+'">'+htmlEscape(z.name)+' ('+htmlEscape(z.kind || '')+')</option>'; });
  $('#textZoneSelect').html(options);
  if ((data || []).length > 0) { loadZoneText(data[0].name); }
  else { $('#zoneTextEditor').val('; No zones returned by PowerDNS.'); }
}
function loadTextZones(){
  $('#zoneTextEditor').val('; Loading zones...');
  ajaxCall('/api/powerdns/zones/search', {}, function(data){
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    renderTextZoneOptions(data || []);
  });
}
function loadZoneText(zone){
  selectedTextZone = normalizeZoneName(zone);
  $('#textZoneSelect').val(selectedTextZone);
  $('#zoneTextEditor').val('; Loading ' + selectedTextZone + ' ...');
  ajaxCall('/api/powerdns/zones/exportText/' + encodeURIComponent(selectedTextZone), {}, function(data){
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    $('#zoneTextEditor').val(data.text || '');
    $('#textRecordCount').text((data.count || 0) + ' RRsets');
  });
}
function saveZoneText(){
  var payload = { zone: normalizeZoneName(), text: $('#zoneTextEditor').val() };
  if (!payload.zone) { showMessage(BootstrapDialog.TYPE_WARNING, 'Missing field', 'Zone is required.'); return; }
  BootstrapDialog.confirm({
    title: 'Apply text zone changes',
    message: 'This will replace non-SOA RRsets in ' + payload.zone + ' with the records represented in the text editor. Continue?',
    type: BootstrapDialog.TYPE_WARNING,
    callback: function(result) {
      if (!result) { return; }
      $('#saveTextBtn_progress').addClass('fa fa-spinner fa-pulse');
      ajaxCall('/api/powerdns/zones/importText', payload, function(data){
        $('#saveTextBtn_progress').removeClass('fa fa-spinner fa-pulse');
        if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
        showMessage(BootstrapDialog.TYPE_SUCCESS, 'PowerDNS', 'Text zone changes applied.');
        loadZoneText(payload.zone);
      });
    }
  });
}
$(document).ready(function(){
  $('#textZoneSelect').change(function(){ loadZoneText($(this).val()); });
  $('#refreshTextZonesBtn').click(loadTextZones);
  $('#reloadTextBtn').click(function(){ loadZoneText(); });
  $('#saveTextBtn').click(saveZoneText);
  loadTextZones();
});
</script>
<ul class="nav nav-tabs" role="tablist">
  <li><a href="/ui/powerdns/general/index">Settings</a></li>
  <li><a href="/ui/powerdns/zones/index">Zones</a></li>
  <li class="active"><a href="/ui/powerdns/text/index">Text edit</a></li>
</ul>
<div class="content-box">
  <div class="pdns-text-toolbar">
    <label for="textZoneSelect" class="control-label">Zone</label>
    <select id="textZoneSelect" class="form-control input-sm"></select>
    <button id="refreshTextZonesBtn" type="button" class="btn btn-xs btn-default bootgrid-tooltip" title="Refresh zones"><span class="fa fa-refresh"></span> Refresh</button>
    <button id="reloadTextBtn" type="button" class="btn btn-xs btn-default bootgrid-tooltip" title="Reload current text"><span class="fa fa-undo"></span> Reload</button>
    <button id="saveTextBtn" type="button" class="btn btn-xs btn-primary bootgrid-tooltip" title="Apply text changes"><span class="fa fa-save"></span> Apply text <i id="saveTextBtn_progress"></i></button>
    <span id="textRecordCount" class="text-muted"></span>
  </div>
  <textarea id="zoneTextEditor" class="form-control" spellcheck="false"></textarea>
  <p class="pdns-text-help">
    Text format: one RRset per line: <code>name TTL TYPE value</code>. Empty lines and <code>;</code> comments are ignored.
    Multiple identical <code>name TTL TYPE</code> lines become multiple records in the same RRset. SOA records are preserved unless edited in the PowerDNS API directly.
  </p>
</div>
