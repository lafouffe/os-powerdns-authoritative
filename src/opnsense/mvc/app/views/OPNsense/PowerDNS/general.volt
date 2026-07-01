<script>
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
    $('#startAct').click(function(){ ajaxCall('/api/powerdns/service/start', {}, function(data){ updateServiceStatusUI(data['response']); }); });
    $('#stopAct').click(function(){ ajaxCall('/api/powerdns/service/stop', {}, function(data){ updateServiceStatusUI(data['response']); }); });
    $('#restartAct').click(function(){ ajaxCall('/api/powerdns/service/restart', {}, function(data){ updateServiceStatusUI(data['response']); }); });
});
</script>
<ul class="nav nav-tabs" role="tablist">
  <li class="active"><a href="/ui/powerdns/general/index">Settings</a></li>
  <li><a href="/ui/powerdns/zones/index">Zones</a></li>
</ul>
<div class="content-box" style="padding-bottom: 1.5em;">
    {{ partial('layout_partials/base_form', ['fields':generalForm,'id':'frm_general_settings']) }}
    <div class="col-md-12"><hr />
        <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save & Apply') }}</b> <i id="saveAct_progress"></i></button>
        <button class="btn btn-success" id="startAct" type="button">{{ lang._('Start') }}</button>
        <button class="btn btn-warning" id="restartAct" type="button">{{ lang._('Restart') }}</button>
        <button class="btn btn-danger" id="stopAct" type="button">{{ lang._('Stop') }}</button>
    </div>
</div>
