package Cpanel::Config::ConfigObj;

# cpanel - Cpanel/Config/ConfigObj.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Manage configuration of Features

use cPstrict;

use Cpanel::Config::ConfigObj::Interface::Meta       ();
use Cpanel::Config::ConfigObj::Interface::Config::v1 ();    # PPI USE OK -- dynamic usage v${version}
use Cpanel::Config::ConfigObj::Interface::Config::v2 ();    # PPI USE OK -- dynamic usage v${version}
use Cpanel::Server::Type::Profile                    ();
use Cpanel::StringFunc::Case                         ();
use Cpanel::JSON                                     ();
use Cpanel::LoadModule                               ();
use Cpanel::Version                                  ();
use Cpanel::Debug                                    ();
use Try::Tiny;

#######
# ATM, there is little way for the current pattern to automagically deal
#  with an object that is spawned with a specific version that no longer
#  supports certain behaviors or maps for legacy purposes, and can communicate
#  that with the caller or act on their behalf...such situations must be
#  manually dealt with/anticipated by the caller...
#  ...Instantiate two (or more) objects, each of a different, behavior specific
#  version. Actions should be readily accessible for doing/undoing/munging as
#  the caller needs.
########

###### VARIABLES #######

our $VERSION = '1.0';

our $DEV_MODE   = 0;
our $DRIVER_DIR = '/usr/local/cpanel/Cpanel/Config/ConfigObj/Driver';    # Must update Whostmgr::ACLS::Cache as well if this changes:

my $drivers;
my $interface_specs;

# Error constants
use constant E_ACTION          => 'Invalid Action';
use constant E_ACTION_READONLY => 'Invalid Action for Read-only';
use constant E_USER_SOFTWARE   => 'Invalid Feature Specified';
use constant E_USER_ACTION     => 'Invalid Action Specified';
use constant E_USER_INPUT      => 'Invalid Input';
use constant E_VERSION         => 'Invalid Version';
use constant E_ERROR           => 'Internal Error';
use constant E_ACTION_TASK     => 'Action Error';

######## FUNCTIONS #########

# pass a positive value to enable dev mode, which will include example drivers
sub set_development_mode {
    my $state = shift || 0;
    $Cpanel::Config::ConfigObj::DEV_MODE = $state;
}

# get the current version as specified
sub version {
    my $detail = shift;
    if ( ref $detail ) {
        $detail = shift;
    }
    $detail ||= '';

    my @version_segments = split( /\./, $VERSION );

    if ( $detail =~ m/^major$/ ) {
        return $version_segments[0];
    }

    return $VERSION;
}

sub _module_check {
    my (%opts) = @_;
    my %default_opts = ( 'log_info' => 0, 'log_warn' => 0 );
    %opts = ( %default_opts, %opts );
    if ( !$opts{'module_path'} ) {
        Cpanel::Debug::log_warn("Invalid module path provided");
        return;
    }

    if ( $INC{ $opts{'module_path'} } ) {
        return 1;
    }

    my $module_name = $opts{'module_name'} || $opts{'module_path'};
    if ( $opts{'log_info'} ) {
        Cpanel::Debug::log_info("Failed to import $module_name: $opts{'error'}");
    }
    elsif ( $opts{'log_warn'} ) {
        Cpanel::Debug::log_warn("Failed to import $module_name: $opts{'error'}");
    }
    return;
}

sub _unload_if_auto_enabled {
    my ( $module, $meta ) = @_;

    if ( $meta->can('auto_enable') and 1 == $meta->auto_enable ) {
        Cpanel::LoadModule::load_perl_module('Symbol');

        # use core module, Symbol, to aggressively remove all entries from
        # the symbol table for the module that will not be used in the Feature Showcase
        Symbol::delete_package($module);
        Symbol::delete_package($meta);
        return 1;
    }
    return 0;
}

# Internal use: get a hash of drivers and hash of specs in use
#  NOTE: the value assigned to the driver key may not be an obj, as this is
#  primary for populating the private hash for this class...if you need the
#  driver obj, use this only to get the list of available drivers: use the
#  get_driver() method to fetch a fully-formed obj
sub get_available_drivers {    ## no critic(Subroutines::ProhibitExcessComplexity) -- JUST BARELY. When V1 drivers are deprecated, this will clear up.
    my ( $specific_version, $force_read, $load_auto_enabled ) = @_;

    # aggregate only a specific version?
    if ( defined $specific_version && ( $specific_version !~ m/^\d+/ || $specific_version =~ m/\.\./ ) ) {
        Cpanel::Debug::log_warn("Invalid version specified: $specific_version");
        return;
    }

    if ( !$drivers || $force_read ) {
        if ( opendir( my $dh, $DRIVER_DIR ) ) {
          LOAD_DRIVERS:
            while ( my $item = readdir($dh) ) {
                if ( $item =~ m/(^[a-z][a-z0-9_]*)\.json$/ ) {
                    my $driver_name = $1;
                    next LOAD_DRIVERS if $driver_name =~ /^example_driver/ && !$DEV_MODE;
                    get_json_driver( $item, $driver_name, $load_auto_enabled );
                    next LOAD_DRIVERS;
                }

                next if $item !~ m/(^[a-zA-Z][a-zA-Z0-9_\-]*)\.pm$/;
                my $match = $1;
                next if $match eq 'ExampleDriver' && !$DEV_MODE;

                my $module = "Cpanel::Config::ConfigObj::Driver::${match}";
                my $meta   = "Cpanel::Config::ConfigObj::Driver::${match}::META";

                # drivers will likely include related META, but JIC
                my $meta_path = "Cpanel/Config/ConfigObj/Driver/$match/META.pm";

                local $@;
                if ( !Cpanel::Config::ConfigObj::_module_check( 'module_path' => $meta_path ) ) {
                    eval "require $meta; 1;";
                }
                my $err = $@;

                # we want to unload drivers that are auto-enabled by default because they don't need to be in the Feature Showcase
                next LOAD_DRIVERS if !$load_auto_enabled && Cpanel::Config::ConfigObj::_unload_if_auto_enabled( $module, $meta );

                # don't fail for bad driver, simply log and continue iterating
                if (
                    Cpanel::Config::ConfigObj::_module_check(
                        'module_path' => $meta_path,
                        'module_name' => $meta,
                        'log_info'    => 1,
                        'error'       => $err,
                    )
                ) {

                    # able to compile driver and meta so store: driver name, module name, and spec
                    #  NOTE: the object itself will be created on demand via other methods
                    my $spec;
                    if ( $meta->can('spec_version') ) {
                        eval { $spec = $meta->spec_version(); 1 } or do {
                            warn "$meta’s spec_version() method failed: $@";
                        };
                    }
                    else {
                        Cpanel::Debug::log_warn("The module “$meta” is missing the spec_version method. It likely needs “use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);”. For more information see the COMPATIBILITY section in `perldoc /usr/local/cpanel/Cpanel/Config/ConfigObj/Interface/Driver.pod`.");
                    }

                    $spec ||= 1;    # Assume v1 if its missing
                    my $driver_name = Cpanel::StringFunc::Case::ToLower( $meta->get_driver_name() );
                    $interface_specs->{$spec} = [] if !exists $interface_specs->{$spec};
                    push @{ $interface_specs->{$spec} }, $driver_name;
                    $drivers->{$driver_name} = {
                        'module_name'    => $match,
                        'interface_spec' => $spec,
                    };
                }
            }
            closedir($dh);
        }
        else {
            die("Unable to open driver directory: $!");
        }
    }

    # make a clone
    my $clone_drivers = {};
    foreach my $item ( keys %{$drivers} ) {
        my $d = $drivers->{$item};

        next unless _check_roles_for_driver($d);

        # add the driver to clone_drivers
        if ( $item ne $d->{'module_name'} ) {    # fixup module_name
            $clone_drivers->{$item}->{'interface_spec'} = $d->{'interface_spec'};
            $clone_drivers->{$item}->{'module_name'}    = $d->{'module_name'};
        }
        else {                                   # v2+, get all the json in the driver
            $clone_drivers->{$item} = $d;
        }
    }

    if ($specific_version) {
        my $filtered_drivers;
        my $filtered_interface_spec = $interface_specs->{$specific_version} || [];
        foreach ( @{$filtered_interface_spec} ) {
            $filtered_drivers->{$_} = $clone_drivers->{$_};
        }
        return wantarray ? ( $filtered_drivers, { $specific_version => $filtered_interface_spec } ) : $filtered_drivers;    ## no critic qw(Wantarray)
    }

    return wantarray ? ( $clone_drivers, $interface_specs ) : $clone_drivers;                                               ## no critic qw(Wantarray)
}

sub _check_roles_for_driver ($driver) {
    return 1 unless ref $driver && ref $driver->{needs_role};

    my $nr    = $driver->{needs_role};
    my $check = {
        match => $nr->{'match'} // 'all',
        items => $nr->{'roles'} // [],
    };

    return Cpanel::Server::Type::Profile::is_valid_for_profile($check);
}

sub get_json_driver {
    my ( $file, $driver_name, $load_autoenabled ) = @_;
    my $json_driver;
    try {
        $json_driver = Cpanel::JSON::LoadFile( $DRIVER_DIR . '/' . $file );
    }
    catch {
        Cpanel::Debug::log_warn( 'Invalid JSON found in drivers file at: ' . $file . '--' . $_ );
    };
    my $current_version = Cpanel::Version::get_short_release_number();
    return if $json_driver->{'meta'}->{'auto_enable'} && !$load_autoenabled;
    return unless _driver_is_valid( $json_driver, $driver_name );
    my $first_version = $json_driver->{'meta'}->{'content'}->{'first_appears_in'};
    my $last_version  = $json_driver->{'meta'}->{'content'}->{'last_appears_in'};
    return if $first_version > $current_version;
    return if $last_version < $current_version;
    my $spec = $json_driver->{'spec_version'} // 2;
    $interface_specs->{$spec} = [] if !exists $interface_specs->{$spec};
    push @{ $interface_specs->{$spec} }, $driver_name;
    $json_driver->{'meta'}{'content'}{'name'}{'driver'} //= $driver_name;
    $drivers->{$driver_name}                     = $json_driver;
    $drivers->{$driver_name}->{'module_name'}    = $driver_name;
    $drivers->{$driver_name}->{'interface_spec'} = $spec;

    return;
}

# check structural validity of the JSON driver
# At some point later, after some hypothetical v3 driver is introduced, it may be useful
# to abstract this and send it to some other version-specific module. Maybe.
sub _driver_is_valid {
    my ( $json, $driver_name ) = @_;

    my @errors;
    my @warnings;

    my $meta = $json->{'meta'};

    if (   !defined $json->{'spec_version'}
        || !_is_positive_integer( $json->{'spec_version'} ) ) {
        push @warnings, "The spec_version field is missing or invalid. The system will assume a v2 driver.";
    }

    my $validations = {
        'meta' => {
            'field'    => $meta,
            'required' => 1,
            'message'  => 'The meta structure is completely missing.'
        },
        'meta_version' => {
            'field'    => $meta->{'meta_version'},
            'required' => 1,
            'test'     => \&_is_positive_integer,
            'message'  => 'The meta->meta_version field is missing or invalid.',
        },
        'first_appears_in' => {
            'field'    => $meta->{'content'}->{'first_appears_in'},
            'required' => 1,
            'test'     => \&_is_positive_integer,
            'message'  => 'The meta->first_appears_in field is missing or invalid.',
        },
        'last_appears_in' => {
            'field'    => $meta->{'content'}->{'last_appears_in'},
            'required' => 1,
            'test'     => \&_is_positive_integer,
            'message'  => 'The meta->last_appears_in field is missing or invalid.',
        },
        'check_readonly_structure' => {
            'field'   => $json,
            'test'    => \&_check_readonly_structure,
            'message' => 'The meta->content->readonly setting is incompatible with enable and disable definitions. Either readonly must be zero, or you must not override enable and disable methods.',
        },
        'check_autoenable_structure' => {
            'field'   => $json,
            'test'    => \&_check_autoenable_structure,
            'message' => 'Auto-enabled features must have the enable method overridden, or nothing will happen.',
        },
        'check_interactive_structure' => {
            'field'   => $json,
            'test'    => \&_check_interactive_structure,
            'message' => 'You must define either enable and disable overrides or a handle_showcase_submission override for interactive feature showcases.',
        },
        'check_form_structure' => {
            'field'   => $json,
            'test'    => \&_check_form_structure,
            'message' => 'If handle_showcase_structure is defined, you must define readonly to be 1.',
        },
        'enable_method_structure' => {
            'field'   => $json->{'enable'},
            'testif'  => \&_check_method_structure,
            'message' => 'For the enable method override, you must either define module/method/params, or a static value override.',
        },
        'disable_method_structure' => {
            'field'   => $json->{'disable'},
            'testif'  => \&_check_method_structure,
            'message' => 'For the disable method override, you must either define module/method/params, or a static value override.',
        },
        'set_default_method_structure' => {
            'field'   => $json->{'set_default'},
            'testif'  => \&_check_method_structure,
            'message' => 'For the set_default method override, you must either define module/method/params, or a static value override.',
        },
        'precheck_method_structure' => {
            'field'   => $json->{'precheck_method_structure'},
            'testif'  => \&_check_method_structure,
            'message' => 'For the precheck method override, you must either define module/method/params, or a static value override.',
        },
        'handle_showcase_submission_method_structure' => {
            'field'   => $json->{'handle_showcase_submission'},
            'testif'  => \&_check_method_structure,
            'message' => 'For the handle_showcase_submission method override, you must either define module/method/params, or a static value override.',
        },
        'enable_params' => {
            'field'   => $json->{'enable'},
            'testif'  => \&_check_params_is_arrayref,
            'message' => 'The enable->params entry must be an array, even if it is empty.',
        },
        'disable_params' => {
            'field'   => $json->{'disable'},
            'testif'  => \&_check_params_is_arrayref,
            'message' => 'The disable->params entry must be an array, even if it is empty.',
        },
        'set_default_params' => {
            'field'   => $json->{'set_default'},
            'testif'  => \&_check_params_is_arrayref,
            'message' => 'The set_default->params entry must be an array, even if it is empty.',
        },
        'handle_showcase_submission_params' => {
            'field'   => $json->{'handle_showcase_submission'},
            'testif'  => \&_check_params_is_arrayref,
            'message' => 'The handle_showcase_submission->params entry must be an array, even if it is empty.',
        },
        'needs_role' => {
            'field'   => $json->{'needs_role'},
            'testif'  => \&_check_is_hashref,
            'message' => 'The needs_role entry must be a hash.',
        },
    };

    if ( _check_is_hashref( $json->{'needs_role'} ) ) {
        my $nr = $json->{'needs_role'};
        $validations->{'needs_role.match'} = {
            'field'   => $nr->{'match'},
            'testif'  => _check_value_in_list(qw{all any none}),
            'message' => 'The needs_role->match entry must be set to "all", "any" or "none".',
        };
        $validations->{'needs_role.roles'} = {
            'field'   => $nr->{'roles'},
            'testif'  => \&_check_is_arrayref,
            'message' => 'The needs_role->roles entry must be an array.',
        };
    }

  VALIDATION:
    foreach my $key ( keys %{$validations} ) {
        if ( $validations->{$key}->{'required'}
            && !defined $validations->{$key}->{'field'} ) {
            push @errors, $validations->{$key}->{'message'};
            next VALIDATION;
        }

        if ( defined $validations->{$key}->{'test'} ) {
            if ( !eval( $validations->{$key}->{'test'}( $validations->{$key}->{'field'} ) ) ) {    ## no critic qw(ProhibitStringyEval)
                push @errors, $validations->{$key}->{'message'};
            }
        }

        if ( defined $validations->{$key}->{'testif'} && defined $validations->{$key}->{'field'} ) {
            if ( !eval( $validations->{$key}->{'testif'}( $validations->{$key}->{'field'} ) ) ) {    ## no critic qw(ProhibitStringyEval)
                push @errors, $validations->{$key}->{'message'};

            }
        }
    }

    if (@warnings) {
        my $warning_string = "The following non-fatal warnings were in the $driver_name driver:\n";
        foreach my $warning (@warnings) {
            $warning_string .= '     ' . $warning . "\n";
            Cpanel::Debug::log_warn($warning) if $DEV_MODE;                                          #for unit tests!
        }
        $warning_string .= "The $driver_name driver will still function, but possibly not as intended.\n";
        Cpanel::Debug::log_warn($warning_string);
    }

    if (@errors) {
        my $error_string = "The following fatal warnings were in the $driver_name driver:\n";
        foreach my $error (@errors) {
            $error_string .= '     ' . $error . "\n";
            Cpanel::Debug::log_warn($error) if $DEV_MODE;                                            #for unit tests!
        }
        $error_string .= "The $driver_name driver will not be loaded.\n";
        Cpanel::Debug::log_warn($error_string);
        return 0;
    }
    return 1;
}

sub _is_positive_integer {
    my $n = shift;
    return if !defined($n);
    return $n =~ m{^[1-9][0-9]*$};
}

sub _check_value_in_list (@list) {
    return sub ($v) {
        return unless defined $v;
        return if ref $v;
        my $is_valid = grep { $v eq $_ } @list;
        return $is_valid ? 1 : 0;
    };
}

sub _check_readonly_structure {
    my $json = shift;

    return 0 if (
        $json->{'meta'}->{'content'}->{'readonly'}
        && (   defined $json->{'enable'}
            || defined $json->{'disable'} )
    );

    return 1;
}

sub _check_autoenable_structure {
    my $json = shift;

    return 0 if ( $json->{'meta'}->{'auto_enable'}
        && $json->{'meta'}->{'showcase'} == -1
        && !defined $json->{'enable'} );

    return 1;
}

sub _check_interactive_structure {
    my $json = shift;

    return 0
      if (
        !$json->{'meta'}->{'auto_enable'}    # one or the other
        && !$json->{'meta'}->{'content'}->{'readonly'}
        && !( ( defined $json->{'enable'} && defined $json->{'disable'} ) || defined $json->{'handle_showcase_submission'} )
      );

    return 0
      if (
        defined $json->{'enable'}            # ...but never both!
        && defined $json->{'handle_showcase_submission'}
      );

    return 1;
}

sub _check_form_structure {
    my $json = shift;

    return 0
      if ( defined $json->{'handle_showcase_submission'}
        && !$json->{'meta'}->{'content'}->{'readonly'} );

    return 1;
}

sub _check_method_structure {
    my $json = shift;

    return 0 if !(    # One or the other...
        ( defined $json->{'module'} && defined $json->{'method'} && defined $json->{'params'} ) || defined $json->{'static'}
    );
    return 0
      if (            # ...but not both!
        defined $json->{'static'} && ( defined $json->{'module'}
            || defined $json->{'method'}
            || defined $json->{'params'} )
      );

    return 1;
}

sub _check_params_is_arrayref ( $json = undef ) {

    # checking to see that it exists isn't our problem.
    return 1 unless ref $json;

    return _check_is_arrayref( $json->{'params'} );
}

sub _check_is_arrayref ( $entry = undef ) {

    return 1 unless defined $entry;    # ok to be undef

    return ref $entry eq 'ARRAY' ? 1 : 0;
}

sub _check_is_hashref ( $entry = undef ) {

    return 1 unless defined $entry;    # ok to be undef

    return ref $entry eq 'HASH' ? 1 : 0;
}

# get the behavior map of a requested version spec
sub get_behaviors {
    my ($specific_version) = @_;
    my @specs = qw(1 2);                 # this should be appended with new specs as necessary

    # aggregate only a specific version?
    if ( defined $specific_version ) {
        if ( $specific_version !~ m/^\d+/ || $specific_version =~ m/\.\./ ) {
            Cpanel::Debug::log_warn("Invalid version specified: $specific_version");
            return;
        }
        else {
            @specs = ($specific_version);
        }
    }

    my $action_hr;
    foreach my $version (@specs) {
        my $version_spec = "Cpanel::Config::ConfigObj::Interface::Config::v${version}";
        my $spec_path    = "Cpanel/Config/ConfigObj/Interface/Config/v$version.pm";

        next if !Cpanel::Config::ConfigObj::_module_check( 'module_path' => $spec_path, 'module_name' => $version_spec, 'log_warn' => 1, 'error' => 'unknown' );
        $action_hr->{'actions'}->{$version} = eval "${version_spec}::spec_actions()" || {};
    }
    return $action_hr;
}

###### METHODS #######

# constructor
#  builds the dispatch map, which can be affected by $args (a hash ref):
#   'version' => $major_version
#   'software' => $a_custom_software_map eg {lc_name=>case_sensitive_module_name}
#   'actions'  => $a_custom_action-behavior_map {'actions'=>hashrf_from_spec_module}
sub new {
    my ( $class, $args ) = @_;
    if ( ref $args ne 'HASH' ) {
        $args = {};
    }

    my $properties = {
        'software'          => undef,
        'actions'           => undef,
        'error_stack'       => [],
        'scheduler'         => {},
        'notice_stack'      => [],
        'load_auto_enabled' => $args->{'load_auto_enabled'} ? 1 : 0,
    };

    my $version;
    if ( !defined $args->{'version'} ) {
        $properties->{'version'} = version('major');
    }
    else {
        $properties->{'scope_to_version'} = 1;
        $version = $properties->{'version'} = delete $args->{'version'};
    }

    my $version_behaviors = get_behaviors($version);

    if ( ref $version_behaviors ne 'HASH' ) {
        return;
    }

    $properties->{'major_version'} = $version;

    return bless {
        %$properties,
        %$version_behaviors,
        %$args
    }, $class;
}

# for use by classes that implement this via ISA
sub _get_drivers {
    return $_[0]->{'software'} ||= get_available_drivers(
        $_[0]->{'major_version'},       #
        0,                              #
        $_[0]->{'load_auto_enabled'}    #
    );
}

# for use by classes that implement this via ISA
#
# NOTE this should be the entire internal structure, not just the driver object
#  see _set_driver_objects if that is all you intend to set
sub _set_drivers {
    my ( $self, $driver_hr ) = @_;
    if ( ref $driver_hr ne 'HASH' ) {
        $driver_hr = {};
    }
    return $self->{'software'} = $driver_hr;
}

# will 'remove' any pre-existing drivers from internal stash that are not
#  present in the passed hashref
sub _set_driver_objects {
    my ( $self, $driver_hr ) = @_;
    if ( ref $driver_hr ne 'HASH' ) {
        $driver_hr = {};
    }

    my $drivers = $self->_get_drivers();
    foreach my $current_driver ( keys %$drivers ) {
        if ( !exists $driver_hr->{$current_driver} ) {
            delete $drivers->{$current_driver};
        }
        else {
            $self->set_driver( $current_driver, $driver_hr->{$current_driver} );
        }
    }
    return $self;

}

# can work with a named driver.  This references the software stack (which may
#  or may not be affected by classes with implement this class[ via filtering])
sub has_driver {
    my ( $self, $driver_name ) = @_;

    my $drivers = $self->_get_drivers();

    return ( exists $drivers->{$driver_name} ) ? 1 : 0;
}

# add error to error_stack
sub set_notice {
    my ( $self, $note ) = @_;
    push @{ $self->{'notice_stack'} }, $note if defined $note;

    return 1;
}

# return notices as a list
sub notices {
    my ($self) = @_;
    return @{ $self->{'notice_stack'} };
}

# return notices as a list, deleting them from the stack
sub flush_notices {
    my ($self) = @_;
    my @notices = @{ $self->{'notice_stack'} };
    $self->{'notice_stack'} = [];
    return @notices;
}

# add error to error_stack
sub set_error {
    my ( $self, $error_msg, $context, $line ) = @_;
    $context = '' if ( ref $context );
    my $error = ($context) ? $error_msg . ': ' . $context : $error_msg;
    if ( !( -t STDIN && -t STDOUT ) ) {
        Cpanel::Debug::log_warn($error);
    }
    $error = ( defined $line ) ? "$error at line: $line" : $error;
    push @{ $self->{'error_stack'} }, $error;

    return 1;
}

# return errors as a list
sub errors {
    my ($self) = @_;
    return @{ $self->{'error_stack'} };
}

# return errors as a list, deleting them from the stack
sub flush_errors {
    my ($self) = @_;
    my @errors = @{ $self->{'error_stack'} };
    $self->{'error_stack'} = [];
    return @errors;
}

# Dispatch a call to $action for $software, passing it $args
sub action {
    my ( $self, $action, $software, $args ) = @_;

    if ( !$self->_valid_software($software) ) {
        $self->set_error( E_USER_SOFTWARE, $software );
        return;
    }
    elsif ( !$self->_valid_action( $action, $software ) ) {
        $self->set_error( E_USER_ACTION, $action );
        return;
    }

    my $obj     = $self->get_driver($software);
    my $drivers = $self->_get_drivers();

    my $spec_class = 'Cpanel::Config::ConfigObj::Interface::Config::v' . $drivers->{$software}->{'interface_spec'};
    my $meta       = $obj->meta();

    if ( !eval { $obj->isa($spec_class) } ) {
        $self->set_error( E_ERROR, "Invalid obj instance", __LINE__ );
        return;
    }

    #TODO: remove 'meta' logic exception
    elsif ( $action eq 'meta' ) {

        # all specs should implement meta()
        #  this is for interface callers so they can build detail lists of
        #  what software is available
        return $meta;
    }
    elsif ( !$obj->can($action) ) {
        $self->set_error( E_ACTION, "'$action' with '$software'", __LINE__ );
        return;
    }

    return $obj->$action( { 'action' => $action, 'args' => $args } );

}

# call a sub on all drivers (if it exists)
# kinda like a batch 'action' but without validation on input.
# probably should only use this to get lists, and not to 'do things'
sub call_all {
    my ( $self, $sub, $args ) = @_;
    my $data    = {};
    my $drivers = $self->_get_drivers();

    foreach my $drivername ( sort keys %$drivers ) {
        my $obj = $self->get_driver($drivername);
        if ( eval { $obj->can($sub) } ) {
            $data->{$drivername} = $obj->$sub($args);
        }
    }
    return $data;
}

# get locale handle for current user
# NOTE: this will observe the current user, so if $self is in memory, and the
#  process changes REMOTE_USER, we'll spawn a new handle; obviously there
#  are drawbacks from this or the alternative, stateless/persistent methodology
sub get_locale_handle {
    my ($self) = @_;
    return undef if $self->{'disable_locale'};

    my $user = $ENV{'REMOTE_USER'} || 'root';
    if ( !$self->{'locale'}->{'handle'} || $self->{'locale'}->{'user'} ne $user ) {
        my $handle;
        eval {

            # eval by string to keep from adding depend at compile time for
            #  binaries
            require Cpanel;
            require Cpanel::Locale;
            if ( $user ne 'root' ) {
                Cpanel::initcp($user);
            }
            $handle = Cpanel::Locale->get_handle();
            1;
        } or do {
            die("Could not create Locale handle: $@: $!");
        };
        $self->{'locale'}->{'handle'} = $handle;
        $self->{'locale'}->{'user'}   = $user;
    }

    return $self->{'locale'}->{'handle'};
}

sub fetch_meta_interface {
    my ($self) = @_;
    if ( !$self->{'meta_interface'} ) {
        $self->{'meta_interface'} = Cpanel::Config::ConfigObj::Interface::Meta->new( {}, $self );
    }
    $self->{'meta_interface'}->set_locale_handle( $self->get_locale_handle() );

    return $self->{'meta_interface'};
}

sub get_driver {
    my ( $self, $software ) = @_;
    my $software_lc = Cpanel::StringFunc::Case::ToLower($software);

    if ( !$self->_valid_software($software_lc) ) {
        $self->set_error( E_ERROR, "Invalid feature '$software'", __LINE__ );
        return;
    }
    my $drivers = $self->_get_drivers();

    if ( !ref $drivers->{$software_lc}->{'obj'} ) {

        eval {
            my $software_case_on_disk = $drivers->{$software_lc}->{'module_name'};
            if ( $software_case_on_disk ne $software_lc ) {
                my $classname = "Cpanel::Config::ConfigObj::Driver::${software_case_on_disk}";
                Cpanel::LoadModule::load_perl_module($classname);
                $drivers->{$software_lc}->{'obj'} = $classname->init($self);
            }
            else {
                my $classname = 'Cpanel::Config::ConfigObj::Interface::Config::v' . $drivers->{$software_lc}->{'interface_spec'};
                Cpanel::LoadModule::load_perl_module($classname);
                $drivers->{$software_lc}->{'obj'} = $classname->new( $software_lc, $drivers->{$software_lc}, $self );
            }
            1;
        } || do {
            Cpanel::Debug::log_warn("Error while instantiating '$software' object: $@") if $@;
            $self->set_error( E_ERROR, "Failed to instantiate $software obj.", __LINE__ );
            return;
        };
    }
    return $drivers->{$software_lc}->{'obj'};
}

sub set_driver {
    my ( $self, $driver_name, $obj ) = @_;
    if ( !eval { $obj->isa('Cpanel::Config::ConfigObj::Interface::Driver') } ) {
        $self->set_error( E_ERROR, "Invalid object argument: " . ref $obj, __LINE__ );
        return;
    }
    my $drivers = $self->_get_drivers();

    if ( exists $drivers->{$driver_name} ) {
        $drivers->{$driver_name}->{'obj'} = $obj;
    }
    return $obj;
}

# if you call this method, you could probably call _valid_software prior
sub _valid_action {
    my ( $self, $action, $software ) = @_;
    my $drivers = $self->_get_drivers();

    # verify input prior to existence and attempted execution of stored dispatch or sub
    #TODO: remove 'meta' logic exception
    if ( !$action || ref $action || !$software || ref $software || ( !exists $self->{'actions'}->{ $drivers->{$software}->{'interface_spec'} }->{$action} && $action ne 'meta' ) ) {
        return;
    }
    return 1;
}

sub _valid_software {
    my ( $self, $software ) = @_;

    #    $software = $self->_normalize_software_name($software);
    my $drivers = $self->_get_drivers();

    if ( !$software || ref $software || !exists $drivers->{$software} ) {
        return;
    }
    return 1;
}

# return hash ref containing info about the current obj:
#  'version' => it's full version
#  'actions' => ref to it's action-behavior map
#  'software' => ref to it's software map
#
# NOTE: 'actions' (and implicitly 'software') will be limited to version. since
#  the original (atm) design is that subsequent specs will implement prior specs
#  this should not be an issue (but may someday)
sub version_info {
    my ($self) = @_;
    my $version = $self->{'version'};
    if ( $version eq version('major') ) {
        $version = $VERSION;
    }
    my $drivers = $self->_get_drivers();

    return { 'version' => $version, 'actions' => $self->{'actions'}->{ $self->{'version'} }, 'software' => [ keys %{$drivers} ] };
}

my @task_processor_modules = ( 'CpServicesTasks', 'ApacheTasks', 'ProxySubdomains', 'EximTasks', 'CpServicesTasks' );

# List of tasks that are allowed to be queued
sub _is_known_queue_task {
    $_[0] =~ m/^(?:hupcpsrvd|apache_restart|remove_autodiscover_proxy_subdomains \S+|add_autodiscover_proxy_subdomains \S+|buildeximconf|restartsrv \S+)$/ ? 1 : 0;
}

# add item to schedule stack
#  call do_scheduled_task() when ready to perform the subs in the stack
sub schedule {
    my ( $self, $item, $action ) = @_;
    return 1 if ( exists $self->{'scheduler'}->{$item} );

    # Allowing passing as an array -- ORDER MATTERS
    if ( ref $item && ref $item eq 'ARRAY' ) {
        my @tasks = grep { _is_known_queue_task($_) } @{$item};
        Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
        $self->{'scheduler'}->{ join( ',', @{$item} ) } = sub { Cpanel::ServerTasks::queue_task( \@task_processor_modules, @tasks ); };
    }
    elsif ( _is_known_queue_task($item) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
        $self->{'scheduler'}->{$item} = sub { Cpanel::ServerTasks::queue_task( \@task_processor_modules, $item ); };
    }
    elsif ( ref $action eq 'CODE' && !exists $self->{'scheduler'}->{$item} ) {    # don't override previously stored custom action
        $self->{'scheduler'}->{$item} = $action;
    }
    else {
        return;
    }
    return 1;
}

sub do_scheduled_tasks {
    my ($self) = @_;
    foreach my $task ( keys %{ $self->{'scheduler'} } ) {
        if ( ref $self->{'scheduler'}->{$task} eq 'CODE' ) {
            $self->{'scheduler'}->{$task}->();
        }
    }
    $self->{'scheduler'} = {};
    return 1;
}

sub scheduled_tasks {
    my ($self) = @_;
    my @tasks = keys %{ $self->{'scheduler'} };
    return @tasks;
}

sub cancel_all_scheduled_tasks {
    my ($self) = @_;
    $self->{'scheduler'} = {};
    return 1;
}

sub cancel_scheduled_task {
    my ( $self, $task ) = @_;
    if ( exists $self->{'scheduler'}->{$task} ) {
        delete $self->{'scheduler'}->{$task};
    }
    return 1;
}

sub DESTROY {
    my ($self) = @_;
    my @remaining_tasks = $self->scheduled_tasks();
    if ( scalar @remaining_tasks ) {
        Cpanel::Debug::log_warn( 'Caller failed to process scheduled tasks prior to object destruction: ' . join( ', ', @remaining_tasks ) );
    }
    return;
}

# For testing
sub reset_caches {
    undef $drivers;
    undef $interface_specs;

    return;
}

1;
