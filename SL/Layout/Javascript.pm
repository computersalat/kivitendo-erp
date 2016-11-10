package SL::Layout::Javascript;

use strict;
use parent qw(SL::Layout::Base);

use SL::Layout::None;
use SL::Layout::Top;
use SL::Layout::Content;

use List::Util qw(max);
use URI;

sub init_sub_layouts {
  [
    SL::Layout::None->new,
    SL::Layout::Top->new,
    SL::Layout::Content->new,
  ]
}

sub use_javascript {
  my $self = shift;
  qw(
    js/dhtmlsuite/menu-for-applications.js
  ),
  $self->SUPER::use_javascript(@_);
}

sub javascripts_inline {
  $_[0]->SUPER::javascripts_inline,
<<'EOJS'
  DHTMLSuite.createStandardObjects();
  DHTMLSuite.configObj.setImagePath('image/dhtmlsuite/');
  var menu_model = new DHTMLSuite.menuModel();
  menu_model.addItemsFromMarkup('main_menu_model');
  menu_model.init();
  var menu_bar = new DHTMLSuite.menuBar();
  menu_bar.addMenuItems(menu_model);
  menu_bar.setTarget('main_menu_div');
  menu_bar.init();
EOJS
}

sub pre_content {
  $_[0]->SUPER::pre_content .
  $_[0]->presenter->render("menu/menunew",
    force_ul_width  => 1,
    menu            => $_[0]->menu,
    icon_path       => sub { my $img = "image/icons/16x16/$_[0].png"; -f $img ? $img : () },
    max_width       => sub { 10 * max map { length $::locale->text($_->{name}) } @{ $_[0]{children} || [] } },
  );
}

sub stylesheets {
  $_[0]->add_stylesheets(qw(
    dhtmlsuite/menu-item.css
    dhtmlsuite/menu-bar.css
    icons16.css
    menu.css
  ));
  $_[0]->SUPER::stylesheets;
}

1;
