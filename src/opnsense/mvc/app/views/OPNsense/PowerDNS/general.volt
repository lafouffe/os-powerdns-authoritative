<script>
function updateServiceStatusUI(statusText) {
    var status = (statusText || '').toString();
    $('#serviceStatusText').text(status || 'unknown');
    $('#serviceStatusIcon').removeClass('fa-play text-success fa-stop text-danger fa-question-circle text-muted');
    if (status.toLowerCase().indexOf('running') >= 0 || status.toLowerCase().indexOf('is running') >= 0) {
        $('#serviceStatusIcon').addClass('fa-play text-success');
    } else if (status.toLowerCase().indexOf('stopped') >= 0 || status.toLowerCase().indexOf('not running') >= 0) {
        $('#serviceStatusIcon').addClass('fa-stop text-danger');
    } else {
        $('#serviceStatusIcon').addClass('fa-question-circle text-muted');
    }
}
function runServiceAction(action, spinnerId) {
    $(spinnerId).addClass('fa fa-spinner fa-pulse');
    ajaxCall('/api/powerdns/service/' + action, {}, function(data){
        $(spinnerId).removeClass('fa fa-spinner fa-pulse');
        if (data && data['response']) {
            updateServiceStatusUI(data['response']);
        } else {
            ajaxCall('/api/powerdns/service/status', {}, function(status){ updateServiceStatusUI(status['response']); });
        }
    });
}
$(document).ready(function() {
    mapDataToFormUI({'frm_general_settings':'/api/powerdns/general/get'}).done(function(){
        formatTokenizersUI();
        $('.selectpicker').selectpicker('refresh');
    });
    ajaxCall('/api/powerdns/service/status', {}, function(data){ updateServiceStatusUI(data['response']); });
    $('#saveAct').click(function() {
        saveFormToEndpoint(url='/api/powerdns/general/set', formid='frm_general_settings', callback_ok=function() {
            $('#saveAct_progress').addClass('fa fa-spinner fa-pulse');
            ajaxCall('/api/powerdns/service/reconfigure', {}, function(data) {
                mapDataToFormUI({'frm_general_settings':'/api/powerdns/general/get'}).done(function(){
                    formatTokenizersUI();
                    $('.selectpicker').selectpicker('refresh');
                });
                ajaxCall('/api/powerdns/service/status', {}, function(status){ updateServiceStatusUI(status['response']); });
                $('#saveAct_progress').removeClass('fa fa-spinner fa-pulse');
            });
        }, true);
    });
    $('#startAct').click(function(){ runServiceAction('start', '#startAct_progress'); });
    $('#stopAct').click(function(){ runServiceAction('stop', '#stopAct_progress'); });
    $('#restartAct').click(function(){ runServiceAction('restart', '#restartAct_progress'); });
    $('#reloadAct').click(function(){ runServiceAction('reload', '#reloadAct_progress'); });
    $('#statusAct').click(function(){ runServiceAction('status', '#statusAct_progress'); });
});
</script>
<ul class="nav nav-tabs" role="tablist">
  <li class="active"><a href="/ui/powerdns/general/index">Settings</a></li>
  <li><a href="/ui/powerdns/zones/index">Zones</a></li>
  <li><a href="/ui/powerdns/text/index">Text edit</a></li>
</ul>
<div class="content-box" style="padding-bottom: 1.5em;">
    {{ partial('layout_partials/base_form', ['fields':generalForm,'id':'frm_general_settings']) }}
    <div class="col-md-12"><hr />
        <div class="btn-toolbar" role="toolbar" style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
            <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
            <div class="btn-group" role="group" aria-label="PowerDNS service actions">
                <button class="btn btn-default bootgrid-tooltip" id="startAct" type="button" title="{{ lang._('Start service') }}"><span class="fa fa-fw fa-play"></span><span class="hidden-xs"> {{ lang._('Start') }}</span> <i id="startAct_progress"></i></button>
                <button class="btn btn-default bootgrid-tooltip" id="reloadAct" type="button" title="{{ lang._('Reload service') }}"><span class="fa fa-fw fa-refresh"></span><span class="hidden-xs"> {{ lang._('Reload') }}</span> <i id="reloadAct_progress"></i></button>
                <button class="btn btn-default bootgrid-tooltip" id="restartAct" type="button" title="{{ lang._('Restart service') }}"><span class="fa fa-fw fa-repeat"></span><span class="hidden-xs"> {{ lang._('Restart') }}</span> <i id="restartAct_progress"></i></button>
                <button class="btn btn-default bootgrid-tooltip" id="stopAct" type="button" title="{{ lang._('Stop service') }}"><span class="fa fa-fw fa-stop"></span><span class="hidden-xs"> {{ lang._('Stop') }}</span> <i id="stopAct_progress"></i></button>
                <button class="btn btn-default bootgrid-tooltip" id="statusAct" type="button" title="{{ lang._('Refresh service status') }}"><span class="fa fa-fw fa-info-circle"></span><span class="hidden-xs"> {{ lang._('Status') }}</span> <i id="statusAct_progress"></i></button>
            </div>
            <span class="text-muted"><span id="serviceStatusIcon" class="fa fa-fw fa-question-circle text-muted"></span> <code id="serviceStatusText">{{ lang._('unknown') }}</code></span>
        </div>
        <p class="help-block" style="margin-top:8px;">{{ lang._('Save writes the OPNsense configuration and applies PowerDNS rendering/firewall changes. Service actions use the standard configd backend actions.') }}</p>
    </div>
</div>
