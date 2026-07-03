<script>
$(document).ready(function() {
    mapDataToFormUI({'frm_general_settings':'/api/powerdns/general/get'}).done(function(){
        formatTokenizersUI();
        $('.selectpicker').selectpicker('refresh');
        updateServiceControlUI('powerdns');
    });

    $('#reconfigureAct').SimpleActionButton({
        onPreAction: function() {
            const dfObj = new $.Deferred();
            saveFormToEndpoint('/api/powerdns/general/set', 'frm_general_settings', function() {
                dfObj.resolve();
            }, true, function() {
                dfObj.reject();
            });
            return dfObj;
        },
        onAction: function() {
            mapDataToFormUI({'frm_general_settings':'/api/powerdns/general/get'}).done(function(){
                formatTokenizersUI();
                $('.selectpicker').selectpicker('refresh');
                updateServiceControlUI('powerdns');
            });
        }
    });
});
</script>
<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
  <li class="active"><a data-toggle="tab" href="#settings" id="tab_settings">{{ lang._('Settings') }}</a></li>
  <li><a href="/ui/powerdns/zones/index">{{ lang._('Zones') }}</a></li>
  <li><a href="/ui/powerdns/text/index">{{ lang._('Text edit') }}</a></li>
</ul>
<div class="tab-content content-box">
    <div id="settings" class="tab-pane fade in active">
        {{ partial('layout_partials/base_form', ['fields':generalForm,'id':'frm_general_settings']) }}
    </div>
</div>

{{ partial('layout_partials/base_apply_button', {'data_endpoint': '/api/powerdns/service/reconfigure', 'data_service_widget': 'powerdns'}) }}
