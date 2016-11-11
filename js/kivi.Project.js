namespace('kivi.Project', function(ns) {
  'use strict';

  this.reset_search_form = function() {
    $("#filter_table input").val("");
    $("#filter_table input[type=checkbox]").prop("checked", 0);
    $("#filter_table select").each(function(_, e) { e.selectedIndex = 0; });
  };
});
