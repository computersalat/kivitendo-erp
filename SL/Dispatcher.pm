package SL::Dispatcher;

use strict;

BEGIN {
  unshift @INC, "modules/override"; # Use our own versions of various modules (e.g. YAML).
  push    @INC, "modules/fallback"; # Only use our own versions of modules if there's no system version.
  push    @INC, "SL";               # FCGI won't find modules that are not properly named. Help it by inclduging SL
}

use CGI qw( -no_xhtml);
use DateTime;
use English qw(-no_match_vars);
use SL::Auth;
use SL::LXDebug;
use SL::Locale;
use SL::Common;
use SL::Helper::DateTime;
use Form;
use List::Util qw(first);
use File::Basename;

# Trailing new line is added so that Perl will not add the line
# number 'die' was called in.
use constant END_OF_REQUEST => "END-OF-REQUEST\n";

sub new {
  my ($class, $interface) = @_;

  my $self           = bless {}, $class;
  $self->{interface} = lc($interface || 'cgi');

  return $self;
}

sub pre_request_checks {
  if (!$::auth->session_tables_present) {
    if ($::form->{script} eq 'admin.pl') {
      ::run();
      ::end_of_request();
    } else {
      show_error('login/auth_db_unreachable');
    }
  }
  $::auth->expire_sessions;
}

sub show_error {
  $::lxdebug->enter_sub;
  my $template             = shift;
  my $error_type           = shift || '';

  $::locale                = Locale->new($::language);
  $::form->{error}         = $::locale->text('The session is invalid or has expired.') if ($error_type eq 'session');
  $::form->{error}         = $::locale->text('Incorrect password!.')                   if ($error_type eq 'password');
  $::myconfig{countrycode} = $::language;
  $::form->{stylesheet}    = 'css/lx-office-erp.css';

  $::form->header;
  print $::form->parse_html_template($template);
  $::lxdebug->leave_sub;

  ::end_of_request();
}

sub pre_startup_setup {
  eval {
    package main;
    require "config/lx-erp.conf";
  };
  eval {
    package main;
    require "config/lx-erp-local.conf";
  } if -f "config/lx-erp-local.conf";

  eval {
    package main;
    require "bin/mozilla/common.pl";
    require "bin/mozilla/installationcheck.pl";
  } or die $EVAL_ERROR;

  # canonial globals. if it's not here, chances are it will get refactored someday.
  {
    no warnings 'once';
    $::userspath   = "users";
    $::templates   = "templates";
    $::memberfile  = "users/members";
    $::menufile    = "menu.ini";
    $::sendmail    = "| /usr/sbin/sendmail -t";
    $::lxdebug     = LXDebug->new;
    $::auth        = SL::Auth->new;
    $::form        = undef;
    %::myconfig    = ();
    %::called_subs = (); # currently used for recursion detection
  }

  $SIG{__WARN__} = sub {
    $::lxdebug->warn(@_);
  }
}

sub pre_startup_checks {
  ::verify_installation();
}

sub pre_startup {
  pre_startup_setup();
  pre_startup_checks();
}

sub require_main_code {
  $::lxdebug->enter_sub;
  my ($script, $suffix) = @_;

  eval {
    package main;
    require "bin/mozilla/$script$suffix";
  } or die $EVAL_ERROR;

  if (-f "bin/mozilla/custom_$script$suffix") {
    eval {
      package main;
      require "bin/mozilla/custom_$script$suffix";
    };
    $::form->error($EVAL_ERROR) if ($EVAL_ERROR);
  }
  if ($::form->{login} && -f "bin/mozilla/$::form->{login}_$script") {
    eval {
      package main;
      require "bin/mozilla/$::form->{login}_$script";
    };
    $::form->error($EVAL_ERROR) if ($EVAL_ERROR);
  }
  $::lxdebug->leave_sub;
}

sub _require_controller {
  my $controller =  shift;
  $controller    =~ s|[^A-Za-z0-9_]||g;

  eval {
    package main;
    require "SL/Controller/${controller}.pm";
  } or die $EVAL_ERROR;
}

sub _run_controller {
  "SL::Controller::$_[0]"->new->_run_action($_[1]);
}

sub handle_request {
  my $self         = shift;
  $self->{request} = shift;

  $::lxdebug->enter_sub;
  $::lxdebug->begin_request;

  my ($script, $path, $suffix, $script_name, $action, $routing_type);

  $script_name = $ENV{SCRIPT_NAME};

  $self->unrequire_bin_mozilla;

  $::cgi         = CGI->new('');
  $::locale      = Locale->new($::language);
  $::form        = Form->new;
  %::called_subs = ();

  eval { ($routing_type, $script_name, $action) = _route_request($script_name); 1; } or return;

  if ($routing_type eq 'old') {
    $::form->{action}  =  lc $::form->{action};
    $::form->{action}  =~ s/( |-|,|\#)/_/g;

   ($script, $path, $suffix) = fileparse($script_name, ".pl");
    require_main_code($script, $suffix);

    $::form->{script} = $script . $suffix;

  } else {
    _require_controller($script_name);
    $::form->{script} = "controller.pl";
  }

  pre_request_checks();

  eval {
    my $session_result = $::auth->restore_session;
    $::auth->create_or_refresh_session;

    $::form->error($::locale->text('System currently down for maintenance!')) if -e "$::userspath/nologin" && $script ne 'admin';

    if ($script eq 'login' or $script eq 'admin' or $script eq 'kopf') {
      $::form->{titlebar} = "Lx-Office " . $::locale->text('Version') . " $::form->{version}";
      ::run($session_result);

    } else {
      show_error('login/password_error', 'session') if SL::Auth::SESSION_EXPIRED == $session_result;
      %::myconfig = $::auth->read_user($::form->{login});

      show_error('login/password_error', 'password') unless $::myconfig{login};

      $::locale = Locale->new($::myconfig{countrycode});

      show_error('login/password_error', 'password') if SL::Auth::OK != $::auth->authenticate($::form->{login}, $::form->{password}, 0);

      $::auth->set_session_value('login', $::form->{login}, 'password', $::form->{password});
      $::auth->create_or_refresh_session;
      $::auth->delete_session_value('FLASH')->save_session();
      delete $::form->{password};

      if ($action) {
        map { $::form->{$_} = $::myconfig{$_} } qw(stylesheet charset)
          unless $action eq 'save' && $::form->{type} eq 'preferences';

        $::form->set_standard_title;
        if ($routing_type eq 'old') {
          ::call_sub('::' . $::locale->findsub($action));
        } else {
          _run_controller($script_name, $action);
        }
      } else {
        $::form->error($::locale->text('action= not defined!'));
      }
    }

    1;
  } or do {
    if ($EVAL_ERROR ne END_OF_REQUEST) {
      $::form->{label_error} = $::cgi->pre($EVAL_ERROR);
      eval { show_error('generic/error') };
    }
  };

  # cleanup
  $::locale   = undef;
  $::form     = undef;
  $::myconfig = ();
  Form::disconnect_standard_dbh();

  $::lxdebug->end_request;
  $::lxdebug->leave_sub;
}

sub unrequire_bin_mozilla {
  my $self = shift;
  return unless $self->{interface} =~ m/^(?:fastcgi|fcgid|fcgi)$/;

  for (keys %INC) {
    next unless m#^bin/mozilla/#;
    next if /\bcommon.pl$/;
    next if /\binstallationcheck.pl$/;
    delete $INC{$_};
  }
}

sub _route_request {
  my $script_name = shift;

  return $script_name =~ m/dispatcher\.pl$/ ? ('old',        _route_dispatcher_request())
       : $script_name =~ m/controller\.pl/  ? ('controller', _route_controller_request())
       :                                      ('old',        $script_name, $::form->{action});
}

sub _route_dispatcher_request {
  my $name_re = qr{[a-z]\w*};
  my ($script_name, $action);

  eval {
    die "Unroutable request -- inavlid module name.\n" if !$::form->{M} || ($::form->{M} !~ m/^${name_re}$/);
    $script_name = $::form->{M} . '.pl';

    if ($::form->{A}) {
      $action = $::form->{A};

    } else {
      $action = first { m/^A_${name_re}$/ } keys %{ $::form };
      die "Unroutable request -- inavlid action name.\n" if !$action;

      delete $::form->{$action};
      $action = substr $action, 2;
    }

    delete @{$::form}{qw(M A)};

    1;
  } or do {
    $::form->{label_error} = $::cgi->pre($EVAL_ERROR);
    show_error('generic/error');
  };

  return ($script_name, $action);
}

sub _route_controller_request {
  my ($controller, $action);

  eval {
    $::form->{action}      =~ m|^ ( [A-Z] [A-Za-z0-9_]* ) / ( [a-z] [a-z0-9_]* ) $|x || die "Unroutable request -- inavlid controller/action.\n";
    ($controller, $action) =  ($1, $2);
    delete $::form->{action};

    1;
  } or do {
    $::form->{label_error} = $::cgi->pre($EVAL_ERROR);
    show_error('generic/error');
  };

  return ($controller, $action);
}

sub get_standard_filehandles {
  my $self = shift;

  return $self->{interface} =~ m/f(?:ast)cgi/i ? $self->{request}->GetHandles() : (\*STDIN, \*STDOUT, \*STDERR);
}

package main;

use strict;

sub end_of_request {
  die SL::Dispatcher->END_OF_REQUEST;
}

1;
