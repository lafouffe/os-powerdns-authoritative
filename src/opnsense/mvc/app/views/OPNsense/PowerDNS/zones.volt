<style>
  #pdns-records-table { table-layout: fixed; }
  #pdns-records-table th:nth-child(1) { width: 30%; }
  #pdns-records-table th:nth-child(2) { width: 8%; }
  #pdns-records-table th:nth-child(3) { width: 8%; }
  #pdns-records-table th:nth-child(4) { width: auto; }
  #pdns-records-table th:nth-child(5) { width: 95px; text-align: right; }
  #pdns-records-table td { vertical-align: middle; }
  .pdns-name { font-family: monospace; word-break: break-word; }
  .pdns-record-value {
    max-height: 4.8em;
    overflow: hidden;
    white-space: pre-wrap;
    word-break: break-word;
    font-family: monospace;
    font-size: 12px;
    line-height: 1.2em;
    margin: 0;
    background: transparent;
    border: 0;
    padding: 0;
  }
  .pdns-toolbar { margin-bottom: 10px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .pdns-toolbar .form-control { width: auto; min-width: 260px; }
  .pdns-muted { color: #777; }
  .pdns-actions { white-space: nowrap; text-align: right; }
</style>
<script>
var selectedZone = '';
var rrsets = [];

function htmlEscape(s){ return $('<div/>').text(s === undefined || s === null ? '' : String(s)).html(); }
function rrKey(idx){ return 'rr-' + idx; }
function normalizeZoneName(zone){ return zone || $('#zoneSelect').val() || selectedZone; }

function showMessage(type, title, message) {
  BootstrapDialog.show({type: type, title: title, message: message});
}

function renderZoneOptions(data) {
  var options = '';
  (data || []).forEach(function(z){
    options += '<option value="'+htmlEscape(z.name)+'">'+htmlEscape(z.name)+' ('+htmlEscape(z.kind || '')+')</option>';
  });
  $('#zoneSelect').html(options);
  if ((data || []).length > 0) {
    loadZone(data[0].name);
  } else {
    $('#recordsBody').html('<tr><td colspan="5" class="text-muted">No zones returned by PowerDNS.</td></tr>');
  }
}

function loadZones(){
  $('#recordsBody').html('<tr><td colspan="5" class="text-muted">Loading zones...</td></tr>');
  ajaxCall('/api/powerdns/zones/search', {}, function(data){
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    renderZoneOptions(data || []);
  });
}

function loadZone(zone){
  selectedZone = normalizeZoneName(zone);
  $('#zoneSelect').val(selectedZone);
  $('#currentZone').text(selectedZone || '');
  $('#recordsBody').html('<tr><td colspan="5" class="text-muted">Loading records...</td></tr>');
  ajaxCall('/api/powerdns/zones/get/' + encodeURIComponent(selectedZone), {}, function(data){
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    rrsets = (data.rrsets || []).slice().sort(function(a, b){
      return ((a.name || '') + (a.type || '')).localeCompare((b.name || '') + (b.type || ''));
    });
    renderRecords();
  });
}

function renderRecords(){
  var rows = '';
  rrsets.forEach(function(rr, idx){
    var values = (rr.records || []).map(function(r){ return r.content; }).join('\n');
    rows += '<tr data-rr-index="'+idx+'">' +
      '<td class="pdns-name" title="'+htmlEscape(rr.name)+'">'+htmlEscape(rr.name)+'</td>' +
      '<td><span class="label label-default">'+htmlEscape(rr.type)+'</span></td>' +
      '<td>'+htmlEscape(String(rr.ttl || ''))+'</td>' +
      '<td><pre class="pdns-record-value" title="'+htmlEscape(values)+'">'+htmlEscape(values)+'</pre></td>' +
      '<td class="pdns-actions">' +
        '<button type="button" class="btn btn-xs btn-default bootgrid-tooltip" title="Edit" onclick="openEditRecord('+idx+')"><span class="fa fa-fw fa-pencil"></span></button> ' +
        '<button type="button" class="btn btn-xs btn-default bootgrid-tooltip" title="Delete" onclick="deleteRecord('+idx+')"><span class="fa fa-fw fa-trash-o"></span></button>' +
      '</td>' +
      '</tr>';
  });
  if (!rows) {
    rows = '<tr><td colspan="5" class="text-muted">No records in this zone.</td></tr>';
  }
  $('#recordsBody').html(rows);
  $('#recordCount').text(rrsets.length + ' RRsets');
}

function openAddRecord(){
  $('#dialogRecordTitle').text('Add DNS record');
  $('#recordZone').val(selectedZone);
  $('#recordName').val(selectedZone ? selectedZone : '');
  $('#recordType').val('A');
  $('#recordTtl').val('300');
  $('#recordValues').val('');
  $('#dialogRecord').modal('show');
}

function openEditRecord(idx){
  var rr = rrsets[idx];
  if (!rr) { return; }
  var values = (rr.records || []).map(function(r){ return r.content; }).join('\n');
  $('#dialogRecordTitle').text('Edit DNS record');
  $('#recordZone').val(selectedZone);
  $('#recordName').val(rr.name);
  $('#recordType').val(rr.type);
  $('#recordTtl').val(rr.ttl || 300);
  $('#recordValues').val(values);
  $('#dialogRecord').modal('show');
}

function saveRecord(){
  var payload = {
    zone: $('#recordZone').val(),
    name: $('#recordName').val(),
    type: $('#recordType').val(),
    ttl: $('#recordTtl').val(),
    records: $('#recordValues').val()
  };
  if (!payload.zone || !payload.name || !payload.type || !payload.ttl) {
    showMessage(BootstrapDialog.TYPE_WARNING, 'Missing field', 'Zone, name, type and TTL are required.');
    return;
  }
  $('#saveRecordBtn').prop('disabled', true);
  ajaxCall('/api/powerdns/zones/setRecord', payload, function(data){
    $('#saveRecordBtn').prop('disabled', false);
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    $('#dialogRecord').modal('hide');
    loadZone(payload.zone);
  });
}

function deleteRecord(idx){
  var rr = rrsets[idx];
  if (!rr) { return; }
  if (!confirm('Delete RRset ' + rr.name + ' ' + rr.type + ' ?')) { return; }
  ajaxCall('/api/powerdns/zones/deleteRecord', {
    zone: selectedZone,
    name: rr.name,
    type: rr.type
  }, function(data){
    if (data && data.error) { showMessage(BootstrapDialog.TYPE_DANGER, 'PowerDNS error', data.error); return; }
    loadZone(selectedZone);
  });
}

$(document).ready(function(){
  $('#zoneSelect').change(function(){ loadZone($(this).val()); });
  $('#refreshZonesBtn').click(loadZones);
  $('#addRecordBtn, #addRecordFooterBtn').click(openAddRecord);
  $('#saveRecordBtn').click(saveRecord);
  loadZones();
});
</script>
<ul class="nav nav-tabs" role="tablist">
  <li><a href="/ui/powerdns/general/index">Settings</a></li>
  <li class="active"><a href="/ui/powerdns/zones/index">Zones</a></li>
</ul>
<div class="content-box">
  <div class="pdns-toolbar">
    <label for="zoneSelect" class="control-label">Zone</label>
    <select id="zoneSelect" class="form-control input-sm"></select>
    <button id="refreshZonesBtn" type="button" class="btn btn-xs btn-default"><span class="fa fa-refresh"></span> Refresh</button>
    <button id="addRecordBtn" type="button" class="btn btn-xs btn-primary"><span class="fa fa-plus"></span> Add record</button>
    <span id="recordCount" class="pdns-muted"></span>
  </div>

  <table id="pdns-records-table" class="table table-condensed table-hover table-striped">
    <thead>
      <tr>
        <th>Name</th>
        <th>Type</th>
        <th>TTL</th>
        <th>Value</th>
        <th class="pdns-actions">Commands</th>
      </tr>
    </thead>
    <tbody id="recordsBody"></tbody>
    <tfoot>
      <tr>
        <td colspan="4"><span class="pdns-muted">Values are wrapped and clipped for readability; open a record to edit the full content.</span></td>
        <td class="pdns-actions"><button id="addRecordFooterBtn" type="button" class="btn btn-xs btn-default"><span class="fa fa-plus"></span></button></td>
      </tr>
    </tfoot>
  </table>
</div>

<div class="modal fade" id="dialogRecord" tabindex="-1" role="dialog" aria-labelledby="dialogRecordTitle">
  <div class="modal-dialog modal-lg" role="document">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
        <h4 class="modal-title" id="dialogRecordTitle">Edit DNS record</h4>
      </div>
      <div class="modal-body">
        <form class="form-horizontal" id="recordForm">
          <div class="form-group"><label class="col-sm-2 control-label">Zone</label><div class="col-sm-10"><input class="form-control" id="recordZone" placeholder="example.org."></div></div>
          <div class="form-group"><label class="col-sm-2 control-label">Name</label><div class="col-sm-10"><input class="form-control" id="recordName" placeholder="www.example.org."></div></div>
          <div class="form-group"><label class="col-sm-2 control-label">Type</label><div class="col-sm-10"><select class="form-control" id="recordType"><option>A</option><option>AAAA</option><option>CNAME</option><option>MX</option><option>NS</option><option>TXT</option><option>CAA</option><option>SRV</option></select></div></div>
          <div class="form-group"><label class="col-sm-2 control-label">TTL</label><div class="col-sm-10"><input class="form-control" id="recordTtl" value="300"></div></div>
          <div class="form-group"><label class="col-sm-2 control-label">Values</label><div class="col-sm-10"><textarea class="form-control" id="recordValues" rows="6" placeholder="One record content per line"></textarea><span class="help-block">One PowerDNS record content per line. TXT values should include quotes when needed.</span></div></div>
        </form>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn btn-primary" id="saveRecordBtn"><span class="fa fa-save"></span> Save</button>
      </div>
    </div>
  </div>
</div>
