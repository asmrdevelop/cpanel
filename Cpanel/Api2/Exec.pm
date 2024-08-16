package Cpanel::Api2::Exec;

# cpanel - Cpanel/Api2/Exec.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic(TestingAndDebugging::RequireUseWarnings) -- This is older code and has not been tested for warnings safety yet.

use experimental 'signatures';

# This will already be loaded if needed
# Do not include for memory
#use Cpanel                 ();
use Cpanel::APICommon::Persona                  ();
use Cpanel::Config::LoadCpUserFile::CurrentUser ();
use Cpanel::EventHandler                        ();
use Cpanel::JSONAPI                             ();
use Cpanel::LoadModule                          ();
use Cpanel::Exception                           ();
use Cpanel::Debug                               ();
use Cpanel::Parser::Vars                        ();

my %_Api2_Funcname_Cache;

#For API calls that implement their own sort/filter/paginate logic.
our %STATE;

sub api2_preexec {
    my ( $module, $func ) = @_;

    if ( exists $_Api2_Funcname_Cache{$module}{$func} ) {
        return $_Api2_Funcname_Cache{$module}{$func};
    }
    else {
        $Cpanel::context = $module;
        ## UAPI: was tr{a-z}{A-Z} (makes upper case); in contrast to api2_exec (makes lower case);
        ##   possibly related: FB cases 51989 and 55041
        $Cpanel::context =~ tr{A-Z}{a-z};
        delete $Cpanel::CPERROR{$Cpanel::context};

        Cpanel::LoadModule::loadmodule($module);
        my $apiref = "Cpanel::${module}"->can('api2');
        if ( ref $apiref ne 'CODE' ) {
            $Cpanel::CPERROR{$Cpanel::context} = "API2: Could not locate function Cpanel::${module}::api2!";
            return;
        }

        $apiref = $apiref->($func);
        $apiref = \%{$apiref} if ref $apiref eq "HASH";

        if ( !defined($apiref) ) {
            Cpanel::Debug::log_warn("API2: ${func} is missing from Cpanel::${module}'s api2 function.  Perhaps you misspelled $func.");
            return;
        }
        elsif ( !exists $apiref->{'func'} ) {
            $apiref->{'func'} = 'api2_' . $func;
        }
        $apiref->{'engine'} ||= 'hasharray';
        $_Api2_Funcname_Cache{$module}{$func} = $apiref;
        return $apiref;
    }
}

my $locale;

sub _locale {
    require Cpanel::Locale;
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

sub api2_exec {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my ( $module, $func, $apiref, $rCFG ) = @_;

    if ( ref $rCFG ne 'HASH' ) {
        $rCFG = {};
    }

    my $dataref;

    my $LCmodule = $module;
    $LCmodule =~ tr{A-Z}{a-z};
    $Cpanel::context = $LCmodule;
    delete $Cpanel::CPERROR{$Cpanel::context};

    ## %status is used by JSON and XML calls; contains keys of 'preevent', 'event', and 'postevent'
    my %status;

    my $full_module   = "Cpanel::${module}";
    my $func_name     = $apiref->{func};
    my $full_function = "${full_module}::$func_name";

    if ( my $err = _get_persona_error($rCFG) ) {
        $Cpanel::CPERROR{$Cpanel::context} = $err;
        return _api2_error();
    }

    my $feature_flag = $apiref->{needs_feature_flag};
    if ($feature_flag) {
        require Cpanel::FeatureFlags::Cache;
        if ( !Cpanel::FeatureFlags::Cache::is_feature_enabled($feature_flag) ) {
            $Cpanel::CPERROR{$Cpanel::context} = _locale()->maketext('Unknown API requested.');
            return _api2_error();
        }
    }

    {
        require Cpanel::Security::Authz;

        local $@;
        if ( !eval { Cpanel::Security::Authz::verify_user_meets_requirements( $Cpanel::user, $apiref ); 1 } ) {
            $Cpanel::CPERROR{$Cpanel::context} = $@->to_locale_string_no_id();
        }
    }

    my @results = _delegate_to_worker_if_defined( $apiref, $module, $func, $rCFG );
    return @results if @results;

    local $ENV{'REMOTE_PASSWORD'}   = $Cpanel::userpass     if ( $Cpanel::NEEDSREMOTEPASS{$module} );    #TEMP_SESSION_SAFE
    local $ENV{'SESSION_TEMP_PASS'} = $Cpanel::tempuserpass if ( $Cpanel::NEEDSREMOTEPASS{$module} );

    if ( !$Cpanel::CPERROR{$Cpanel::context} && Cpanel::JSONAPI::is_json_request() && Cpanel::JSONAPI::has_nested_structures($rCFG) ) {
        $Cpanel::CPERROR{$Cpanel::context} = "API2: $full_function does not support complex data requests.";
    }

    if ( length $Cpanel::CPERROR{$Cpanel::context} ) {
        return _api2_error();
    }

    if ( $Cpanel::EventHandler::hooks || $Cpanel::EventHandler::customEvents ) {
        my ( $ran, $result, $msgs ) = Cpanel::EventHandler::pre_event( 2, 'pre', $module, $func, $rCFG, $dataref );
        if ($ran) {
            $status{'preevent'} = { 'result' => $result ? 1 : 0 };
            if ( !$result ) {
                if ( $Cpanel::CPVAR{'debug'} ) {
                    Cpanel::Debug::log_info("Custom event handler returned false; aborting command [${module}::$func]");
                }

                $msgs //= ['An unknown error occurred.'];
                $Cpanel::CPERROR{$Cpanel::context} = join( qq{\n}, @{$msgs} );

                $status{'preevent'}->{'reason'} = $Cpanel::CPERROR{$Cpanel::context};
                return $dataref, \%status;
            }
        }
    }

    ## note: in each of the below handler's, $dataref is assigned to. in other words, the $dataref
    ##   passed to (and possibly utilized by) the pre-eventhandler is not merged with the $dataref
    ##   from the actual event.

    my $exec_err;

    #So that no other API 2 calls will see the %STATE that this call reports.
    local %STATE;

    if ( $apiref->{'engine'} eq 'hasharray' || $apiref->{'engine'} =~ /^array/ ) {
        ( local $SIG{'__DIE__'} = sub { } ) if $Cpanel::Parser::Vars::altmode;

        my $func_cr = $full_module->can($func_name);
        if ($func_cr) {

            ## cpdev: $dataref = [ Cpanel::$Module::$method(%args) ];
            ## note: the enclosing [] is deref'd a few lines down
            local $@;
            my $ok = eval { $dataref = [ $func_cr->(%$rCFG) ]; 1 };
            $exec_err = $@;

            if ($ok) {
                $status{'event'} = { 'result' => 1 };
            }
            else {
                $Cpanel::CPERROR{$Cpanel::context} = Cpanel::Exception::get_string($exec_err);

                $status{'event'} = {
                    'result' => 0,
                    'reason' => $Cpanel::CPERROR{$Cpanel::context},
                };
            }
        }
        else {
            $Cpanel::CPERROR{$Cpanel::context} = "API2: Could not locate function $full_function!";
        }
    }

    if ( !defined($dataref) ) {
        Cpanel::Debug::log_warn( "Unable to run [$full_function(" . join( ' ', %{$rCFG} ) . ")]: $! ($exec_err)" );
        $Cpanel::CPERROR{$Cpanel::context} ||= $!;
    }
    elsif ( ref ${$dataref}[0] eq 'ARRAY' ) {
        $dataref = ${$dataref}[0];
    }

    $Cpanel::CPVAR{'last_api2_has_data'} = ( ( ref $dataref eq 'ARRAY' ) && @{$dataref} && defined $dataref->[0] ) ? 1 : 0;

    if ( $Cpanel::EventHandler::hooks || $Cpanel::EventHandler::customEvents ) {
        my ( $ran, $result ) = Cpanel::EventHandler::post_event( 2, 'post', $module, $func, $rCFG, $dataref );
        if ($ran) {
            $status{'postevent'} = { 'result' => $result ? 1 : 0 };
            if ( !$result ) {
                $status{'postevent'}->{'reason'} = $Cpanel::CPERROR{$Cpanel::context};
                return $dataref, \%status;
            }
        }
    }

    # This the function that was actually called before we map it to the actual perl function
    # We need to store the state here as where the perl maps to can change
    my $state_key = "Cpanel::${module}::${func}";

    ## NOTE: The %STATE hash is where API2 tracks what code underneath has
    ## already sorted, filtered, or paginated. In the case of MySQL-driven
    ## functions, for example (e.g., EmailTrack::Search), the MySQL backend
    ## does that stuff, so that function sets %STATE entries to prevent this
    ## layer from re-transforming it. Another example is list_pops_with_disk,
    ## which does UAPI "in-processing" to reduce wasteful data fetching; UAPI
    ## also sets %STATE variables that correspond to the processing that it
    ## has implemented in this case.
    if ( defined($dataref) && ref $rCFG eq 'HASH' ) {
        if ( $rCFG->{'api2_columns'} ) {
            require Cpanel::Api2::Columns;
            $dataref = Cpanel::Api2::Columns::apply( $rCFG, $dataref, \%status );
        }
        if ( $rCFG->{'api2_filter'} ) {
            $status{'records_before_filter'} = $STATE{$state_key}{'records_before_filter'};
            if ( !defined $status{'records_before_filter'} ) {
                $status{'records_before_filter'} = scalar @$dataref;
            }

            require Cpanel::Api2::Filter;
            $dataref = Cpanel::Api2::Filter::apply( $rCFG, $dataref, $apiref, $STATE{$state_key}{'filtered'}, \%status );
        }
        if ( $rCFG->{'api2_sort'} ) {
            require Cpanel::Api2::Sort;
            $dataref = Cpanel::Api2::Sort::apply( $rCFG, $dataref, $apiref, $STATE{$state_key}{'sorted'} );
        }
        if ( exists $rCFG->{'api2_paginate'} ) {
            require Cpanel::Api2::Paginate;
            if ( !$STATE{$state_key}{'paginated'} ) {
                my ( undef, $end_chop ) = Cpanel::Api2::Paginate::setup_pagination_vars( $rCFG, $dataref );
                if ($end_chop) {
                    if ( $rCFG->{'api2_paginate_size'} <= $#$dataref ) {
                        splice( @{$dataref}, $rCFG->{'api2_paginate_size'} );
                    }
                }
            }

            $status{'paginate'} = Cpanel::Api2::Paginate::get_state();
        }
    }

    if ( exists $STATE{$state_key}{'metadata'} ) {
        $status{'metadata'} = $STATE{$state_key}{'metadata'};
    }

    if ( $apiref->{'postfunc'} && ( ref $apiref->{'postfunc'} eq 'CODE' ) ) {
        $apiref->{'postfunc'}->( 'dataref' => $dataref, 'cfgref' => $rCFG );
    }

    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    _log_api_usage( $module, $func ) if $cpconf->{'enable_api_log'};

    return $dataref, \%status;
}

sub _api2_error () {
    return (
        undef,
        {
            event => {
                result => 0,
                reason => $Cpanel::CPERROR{$Cpanel::context},
            }
        },
    );
}

sub _get_persona_error ($args_hr) {
    return undef if !Cpanel::Config::LoadCpUserFile::CurrentUser::load($Cpanel::user)->child_workloads();

    my ($str) = Cpanel::APICommon::Persona::get_expect_parent_error_pieces( $args_hr->{'api2_persona'} );

    return $str;
}

sub _delegate_to_worker_if_defined {
    my ( $apiref, $module, $func, $rCFG ) = @_;

    if ( my $worker_type = $apiref->{'worker_node_type'} ) {
        require Cpanel::LinkedNode::Worker::User;

        my $proxy_result = Cpanel::LinkedNode::Worker::User::call_worker_api2( $worker_type, $module, $func, $rCFG );

        if ($proxy_result) {
            return ( delete $proxy_result->{'data'}, $proxy_result );
        }
    }

    return;
}

sub _log_api_usage {
    my ( $module, $func ) = @_;

    my $call = {
        'call' => "${module}::${func}",
    };
    $call->{'page'}        = $ENV{'SCRIPT_FILENAME'} if defined $ENV{'SCRIPT_FILENAME'};
    $call->{'uri'}         = $ENV{'SCRIPT_URI'}      if defined $ENV{'SCRIPT_URI'};
    $call->{'api_version'} = 'cpapi2';

    require Cpanel::AdminBin::Call;
    Cpanel::AdminBin::Call::call( 'Cpanel', 'api_call', 'LOG', $call );

    return 1;
}

1;
