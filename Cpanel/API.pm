package Cpanel::API;

# cpanel - Cpanel/API.pm                           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::API - “gateway” to the UAPI

=head1 SYNOPSIS

    use Cpanel::API ();

    my $result = Cpanel::API::execute_or_die( 'Module', 'func', \%args );

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::APICommon::Persona                  ();
use Cpanel::Api2::Exec                          ();
use Cpanel::AppSafe                             ();
use Cpanel::Args                                ();
use Cpanel::Config::LoadCpUserFile::CurrentUser ();
use Cpanel::Encoder::Tiny                       ();
use Cpanel::EventHandler                        ();
use Cpanel::Exception                           ();
use Cpanel::LoadModule                          ();
use Cpanel::Locale::Context                     ();
use Cpanel::Debug                               ();
use Cpanel::Math                                ();
use Cpanel::Result                              ();
use Cpanel::Security::Authz                     ();
use Cpanel::StringFunc::Case                    ();
use Cpanel::Parser::Vars                        ();
use Cpanel::Encoder::Tiny                       ();
use Cpanel::JSON                                ();
use Cpanel::JSONAPI                             ();

## _execute is called by legacy API1 and API2 tags/calls; prevents the following
##   from happening twice: custom event subsystem, and filter/sort/pagination
## note: most x3 pages call _execute 18 times on Branding::spritelist
sub _execute {
    my ( $module, $function, $args_ref ) = @_;

    my $result = _init_execute( $module, $function );
    return $result if !$result->status();

    local $@;

    #Duplicate so that any changes we make don’t affect the caller.
    $args_ref = defined $args_ref ? {%$args_ref} : {};

    return $result if !_verify_persona( $args_ref, $result );

    my $api_hr = $Cpanel::{'API::'}{"${module}::"}{'API'};
    $api_hr &&= *{$api_hr}{'HASH'};

    _verify_requirements( $result, $function, $api_hr );
    return $result if !$result->status();

    my $worker_result = _delegate_to_worker_if_defined( $api_hr, $module, $function, $args_ref );
    return $worker_result if $worker_result;

    #Convert API 2 filter/sort/paginate meta-arguments into UAPI
    #so that in-processing functions (e.g., Email::list_pops_with_disk)
    #can work with them.
    _make_meta_from_api2_args($args_ref);

    my $args = Cpanel::Args->new($args_ref);

    _run_module_function( $args, $result, $module, $function );

    return $result;
}

sub _verify_persona ( $args_ref, $result ) {
    return 1 if !Cpanel::Config::LoadCpUserFile::CurrentUser::load($Cpanel::user)->child_workloads();

    my ( $msg, $payload ) = Cpanel::APICommon::Persona::get_expect_parent_error_pieces( $args_ref->{'api.persona'} );

    return 1 if !$msg;

    $result->data($payload);

    $result->raw_error($msg);

    $result->status(0);

    return 0;
}

sub _delegate_to_worker_if_defined {
    my ( $api_hr, $module, $function, $args_ref ) = @_;

    my $result;

    my $worker_type = $api_hr && ( $api_hr->{'_worker_node_type'} || $api_hr->{$function}{'worker_node_type'} );

    if ($worker_type) {
        require Cpanel::LinkedNode::Worker::User;
        $result = Cpanel::LinkedNode::Worker::User::call_worker_uapi( $worker_type, $module, $function, $args_ref );
    }

    return $result;
}

sub _verify_requirements {

    my ( $result, $function, $api_hr ) = @_;

    # Right now we support:
    #   1) “_needs_role”, “_needs_feature”, “_needs_feature_flag” for the entire module, OR …
    #   2) “needs_role” and “needs_feature”, “needs_feature_flag” for an individual function.
    #
    # The logic below does NOT support having a function-specific restriction
    # that interacts with the module-wide restriction.
    #
    # Any function without a role or feature restriction will be allowed.

    my $role         = $api_hr->{_needs_role};
    my $feature      = $api_hr->{_needs_feature};
    my $feature_flag = $api_hr->{_needs_feature_flag};

    $api_hr &&= $api_hr->{$function};

    $role         ||= $api_hr->{needs_role};
    $feature      ||= $api_hr->{needs_feature};
    $feature_flag ||= $api_hr->{needs_feature_flag};

    # “allow_demo” is only supported for individual functions as it
    # operates as a whitelist of functions to allow in demo mode.
    #
    # Any function that does not explicitly define allow_demo will be
    # rejected in demo mode.

    my $demo = $api_hr->{allow_demo};

    if ($feature_flag) {
        require Cpanel::FeatureFlags::Cache;
        if ( !Cpanel::FeatureFlags::Cache::is_feature_enabled($feature_flag) ) {
            $result->raw_error( _locale()->maketext('Unknown API requested.') );
            $result->status(0);
            return;
        }
    }

    if ( $role || $feature || !$demo ) {

        my $verify = {
            needs_role    => $role,
            needs_feature => $feature,
            allow_demo    => $demo,
        };

        local $@;
        if ( !eval { Cpanel::Security::Authz::verify_user_meets_requirements( $Cpanel::user, $verify ); 1; } ) {
            $result->raw_error( $@->to_locale_string_no_id() );
            $result->status(0);
        }

    }

    return;
}

sub execute {
    my ( $module, $function, $args_ref ) = @_;

    # Ensure the module is loaded before trying
    # to make the api call
    my $result = _init_execute( $module, $function );
    return $result if !$result->status();

    local $@;

    my $api_version = 3;
    if (   $Cpanel::appname
        && $Cpanel::appname eq 'webmail'
        && !Cpanel::AppSafe::checksafefunc( $module, $function, $api_version ) ) {
        Cpanel::Debug::log_warn( sprintf( "Execution of %s::%s (api version:%s) is not permitted inside of webmail", $module, $function, $api_version ) );
        $result->error( "Execution of [_1]::[_2] (api version:[_3]) is not permitted inside of webmail", $module, $function, $api_version );
        $result->status(0);
        return $result;
    }

    $args_ref = defined $args_ref ? {%$args_ref} : {};

    return $result if !_verify_persona( $args_ref, $result );

    my $api_hr = $Cpanel::{'API::'}{"${module}::"}{'API'};
    $api_hr &&= *{$api_hr}{'HASH'};

    _verify_requirements( $result, $function, $api_hr );
    return $result if !$result->status();

    my $worker_result = _delegate_to_worker_if_defined( $api_hr, $module, $function, $args_ref );
    return $worker_result if $worker_result;

    $api_hr &&= $api_hr->{$function};

    # TODO: Some APIs should be disabled when certain services are disabled, e.g. most methods in Cpanel::API::Ftp
    # should depend on the ftp service being enabled

    my $args;
    {
        local $@;
        eval {
            local $SIG{'__DIE__'};
            $args = Cpanel::Args->new( $args_ref, $api_hr );
            1;
        } or do {
            _handle_eval_fail( $result, $@ );
            return $result;
        };
    }

    _safety_check_args( $args, $result, $module, $function );    # alters $result if safety check fails
    return $result if !$result->status();

    my %invalids = (
        filter     => $args->invalid_filters(),
        sort       => $args->invalid_sorts(),
        pagination => [ $args->invalid_paginate() || () ],
    );

    while ( my ( $xform_type, $invalids_ar ) = each %invalids ) {
        for (@$invalids_ar) {
            $result->message( 'The following “[_1]” arguments are invalid: [_2] ([_3])', $xform_type, Cpanel::JSON::Dump( $_->[0] ), $_->[1]->to_locale_string() );
        }
    }

    local $Cpanel::IxHash::Modify = 'none';

    if ( $Cpanel::EventHandler::hooks || $Cpanel::EventHandler::customEvents ) {
        $result->stage('pre_api');
        my $pre_status = Cpanel::EventHandler::pre_api( $module, $function, $args, $result );
        ## NOTE: a false return from a pre-event signals both an error and a "blocked" event
        $result->status($pre_status);
        return $result unless $pre_status;
        $result->stage(undef);
    }

    _run_module_function( $args, $result, $module, $function );
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    _log_api_usage( $module, $function ) if ( $cpconf->{'enable_api_log'} );
    return $result                       if !$result->status();

    if ( $Cpanel::EventHandler::hooks || $Cpanel::EventHandler::customEvents ) {
        $result->stage('post_api');
        my $post_status = Cpanel::EventHandler::post_api( $module, $function, $args, $result );
        $result->status($post_status);
        return $result unless $post_status;
        $result->stage(undef);
    }

    #NB: Cpanel::Result won't do the same operation twice on the same data.
    if ( ref $result->data() eq 'ARRAY' ) {
        local $@;
        eval {
            local $SIG{'__DIE__'};
            _post_execute_transform( $args, $result );
            1;
        } or do {
            _handle_eval_fail( $result, $@ );
        };
    }

    return $result;
}

=head2 execute_or_die( MODULE, FUNC, ARGS_HR )

The easiest way to run UAPI functions from Perl.
It throws a suitable exception if the API call indicates a failure.
The result is an instance of C<Cpanel::Result>.

=cut

sub execute_or_die {
    my ( $module, $function, $args_ref ) = @_;
    my $result = execute( $module, $function, $args_ref );
    if ( !$result->status ) {
        die $result->errors_as_string;
    }
    return $result;
}

sub get_coderef {
    my ( $module, $function ) = @_;

    require Cpanel::Validate::PackageName;

    Cpanel::Validate::PackageName::validate_or_die($module);

    if ( !_function_is_safe($function) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid [asis,UAPI] function name.", [$function] );
    }

    Cpanel::LoadModule::load_perl_module("Cpanel::API::$module");

    my $coderef = "Cpanel::API::$module"->can($function);

    if ( !$coderef ) {
        die Cpanel::Exception::create( 'FunctionNotImplemented', "The [asis,UAPI] module “[_1]” does not have a function named “[_2]”.", [ $module, $function ] );
    }

    return $coderef;
}

sub _init_execute {
    my ( $module, $function ) = @_;

    my $result = Cpanel::Result->new();

    if ( _function_is_safe($function) ) {
        local $@;
        my $ns_ref = $Cpanel::{'API::'}{"${module}::"};
        $ns_ref &&= *{$ns_ref}{'HASH'};

        #We have to check the namespace's size as well as its existence because
        #require() will create a namespace hash even when it fails to load the module.
        if ( !$ns_ref || !%$ns_ref || !$ns_ref->{$function} ) {

            ## The uAPI presumes 'API::' in the middle
            local $@;
            my $load_ok = eval { Cpanel::LoadModule::load_perl_module("Cpanel::API::$module"); };
            if ( !$load_ok ) {
                my $err = $@;

                Cpanel::Debug::log_warn("Failed to load module “$module”: $err");

                $result->error( "Failed to load module “[_1]”: [_2]", $module, Cpanel::Exception::get_string_no_id($err) );
                $result->status(0);
            }
        }
    }
    else {
        Cpanel::Debug::log_warn("Illegal function name: ${function}");
        $result->error( 'Illegal function name: [_1]', $function );
        $result->status(0);
    }

    return $result;
}

my %function_cache;

sub _run_module_function {
    my ( $args, $result, $module, $function ) = @_;

    local $ENV{'REMOTE_PASSWORD'}   = $Cpanel::userpass     if ( $Cpanel::NEEDSREMOTEPASS{$module} );    #TEMP_SESSION_SAFE
    local $ENV{'SESSION_TEMP_PASS'} = $Cpanel::tempuserpass if ( $Cpanel::NEEDSREMOTEPASS{$module} );
    local $Cpanel::context          = lc $module;

    if ( my $function_cr = $function_cache{"Cpanel::API::${module}::$function"} ||= "Cpanel::API::${module}"->can($function) ) {
        local $@;
        eval {
            local $SIG{'__DIE__'};
            $result->status( scalar $function_cr->( $args, $result ) );
            1;
        } or do {
            _handle_eval_fail( $result, $@ );
        };
    }
    else {
        Cpanel::Debug::log_warn("Could not find “$function” in module “$module”.");
        $result->error( "The system could not find the function “[_1]” in the module “[_2]”.", $function, $module );
        $result->status(0);
    }

    return;
}

sub _post_execute_transform {
    my ( $args, $result ) = @_;
    my $dataref = $result->data();

    ## nothing to do unless the dataset is an array
    return 1 if ref($dataref) ne 'ARRAY';

    ## We only know how to filter/sort on array-of-hashes
    if ( ref( $dataref->[0] ) eq 'HASH' ) {
        $result->apply_any_filters_sorts_pagination($args);

        #NOTE: Would it be useful to put the serialization code in the
        #Filter and Sort objects?

        for my $filter ( @{ $result->unfinished_filters($args) } ) {
            my $filter_str = join( ' ', $filter->column(), $filter->type(), Cpanel::JSON::Dump( $filter->term() ) );
            $result->message( 'The following filter did not pertain to this dataset: [_1]', $filter_str );
        }

        for my $sort ( @{ $result->unfinished_sorts($args) } ) {
            my $sort_str = ( $sort->reverse() ? '!' : q{} ) . $sort->column() . ', ' . $sort->method();
            $result->message( 'The following sort did not pertain to this dataset: [_1]', $sort_str );
        }
    }

    $result->force_pagination($args);

    my $pagination = $args->paginate();
    if ( $pagination && defined $result->total_results() ) {
        $result->metadata( 'paginate', _make_paginate_metadata( $pagination, $result ) );
    }

    $result->metadata( 'transformed', 1 );

    return 1;
}

sub _make_paginate_metadata {
    my ( $pagination, $result ) = @_;

    return {
        total_results => $result->total_results(),

        #The rest of these are just cruft. Might as well leave them in, though.
        total_pages      => Cpanel::Math::ceil( $result->total_results() / $pagination->size() ),
        start_result     => 1 + $pagination->start(),
        results_per_page => $pagination->size(),
        current_page     => Cpanel::Math::ceil( ( 1 + $pagination->start() ) / $pagination->size() ),
    };
}

sub _handle_eval_fail {    ##no critic qw(RequireArgUnpacking)
                           # $result  = $_[0]
                           # $err     = $_[1]

    my $err = $_[1];
    if ( UNIVERSAL::isa( $err, 'Cpanel::Exception' ) ) {
        $err = $err->to_locale_string_no_id();
    }
    else {

        # $blessed shouldn’t normally happen but can if, e.g.,
        # an API call loads an external Perl library and that
        # library throws an uncaught exception.
        my $blessed = ref($err) && do {
            require Cpanel::ScalarUtil;
            Cpanel::ScalarUtil::blessed($err);
        };

        $err = "$err" if $blessed;
    }

    $_[0]->raw_error($err);

    $_[0]->status(0);

    return 0;
}

# Useful for API 2 calls that call UAPI internally, though
# this should probably happen at the API 2 layer.
sub _make_meta_from_api2_args {
    my ($args_ref) = @_;

    #Defer to API2's own code for getting filters and sorts.
    if ( $args_ref->{'api2_filter'} ) {
        require Cpanel::Api2::Filter;
        my $filters_ar = Cpanel::Api2::Filter::get_filters($args_ref);
        for my $f ( 0 .. $#$filters_ar ) {
            @{$args_ref}{ map { "api.filter_${_}_$f" } qw( column type term ) } = @{ $filters_ar->[$f] };
        }
    }

    if ( $args_ref->{'api2_sort'} ) {
        require Cpanel::Api2::Sort;
        my $sorts_ar = Cpanel::Api2::Sort::get_sort_func_list($args_ref);
        for my $s ( 0 .. $#$sorts_ar ) {
            @{$args_ref}{ map { "api.sort_${_}_$s" } keys %{ $sorts_ar->[$s] } } = values %{ $sorts_ar->[$s] };
        }
    }

    for my $key ( keys %$args_ref ) {
        if ( index( $key, 'api2_' ) == 0 ) {
            my $val      = delete $args_ref->{$key};
            my $key_frag = substr( $key, 5 );

            #Do pagination "directly".
            if ( index( $key_frag, 'paginate' ) == 0 ) {
                $args_ref->{"api.$key_frag"} = $val;
            }
        }
    }

    return;
}

## Legacy API1 and API2 tags/calls make calls to the unified API (Cpanel/API/$Module.pm);
##   the following method handles common requirements of deprecated calls.
##
## NOTE: Anything that calls a UAPI method that does "in-processing" needs
## to pass in $args_ref->{'api2_state_key'} so that UAPI can tell API 2 that its
## filter/sort/paginate work is done.
##
## As of October 2013, this is only two functions:
##      Email::listlists
##      Email::listpopswithdisk
##
## .. however, if we add "in-processing" to any existing UAPI calls that "power"
## old API 2 calls, those API 2 calls will also need to give 'api2_state_key'.
##
## It *may* be possible to determine this information via caller(), but that's making
## assumptions that may not be apparent to an implementor. The real problem is that this
## module should not be "aware" of API 2 at all; the stuff to package up a UAPI response
## for an API 2 wrapper should be in another module that calls into this one.
## TODO: Fix this problem.
##
sub wrap_deprecated {
    my ( $module, $function, $args_ref ) = @_;

    my $api2_state_key = delete $args_ref->{'api2_state_key'};

    my $result = _execute( $module, $function, $args_ref );

    if ($api2_state_key) {
        _fill_out_api2_state_key_from_result( $api2_state_key, $result );
    }

    ## $args_ref->{'api.quiet'} is used by all API2 calls, and in very rare cases of API1 calls
    ##   (i.e. use if there is double output of the error message; see ::Email's &adddforward)
    my $quiet = defined $args_ref && exists $args_ref->{'api.quiet'} && $args_ref->{'api.quiet'};

    ## added for Email's addautoresponder; note the default of true (when absent)
    my $html_encode_messages = exists $args_ref->{'api.html_encode_messages'} ? $args_ref->{'api.html_encode_messages'} : 1;

    ## no need to examine $result->status(). $function can produces errors, while
    ##   still not being fatal/unsuccessful.

    if ( defined $result->errors() ) {
        my $LCmodule     = Cpanel::StringFunc::Case::ToLower($module);
        my $known_errors = $Cpanel::CPERROR{$LCmodule};
        for my $error ( @{ $result->errors() } ) {

            # only remove duplicate errors already defined ( preserve duplicates from $result )
            next if defined $known_errors && index( $known_errors, $error ) >= 0;
            if ($Cpanel::Parser::Vars::altmode) {
                ## Email's addpop is a good test case for encoding, with:
                ##   $result->error('<script>alert("error")</script>');
                $Cpanel::CPERROR{$LCmodule} .= $error;
            }
            else {
                if ( !$quiet ) {
                    print qq(<br /><font color="#FF0000">) . ( $html_encode_messages ? Cpanel::Encoder::Tiny::safe_html_encode_str($error) : $error ) . qq(</font>\n);
                }
                if ( length $Cpanel::CPERROR{$LCmodule} ) {
                    $Cpanel::CPERROR{$LCmodule} .= "\n";
                }
                $Cpanel::CPERROR{$LCmodule} .= "$error";
            }
        }
    }

    if ( defined $result->messages() ) {
        for my $msg ( @{ $result->messages() } ) {
            ## if !altmode && !quiet
            unless ( $Cpanel::Parser::Vars::altmode || $quiet ) {
                $msg = Cpanel::Encoder::Tiny::safe_html_encode_str($msg) if $html_encode_messages;
                print "<br />$msg\n";
            }
        }
    }
    return $result;
}

#
# In order to tell api2 that its sorting, filtering, and
# pagination have already been completed we need to fill
# the state key with this data (assuming it has been
# sorted, filtered, or paginated).
#
sub _fill_out_api2_state_key_from_result {
    my ( $api2_state_key, $result ) = @_;

    my $api2_state_hr = \%Cpanel::Api2::Exec::STATE;

    my $pagination_obj = $result->finished_paginate();
    if ($pagination_obj) {

        #NOTE: UAPI and API2 "happen" to use the same keys for reporting
        #pagination data to the caller.
        my $metadata_hr = _make_paginate_metadata( $pagination_obj, $result );
        require Cpanel::Api2::Paginate;
        my %uapi_to_cpvar = reverse %Cpanel::Api2::Paginate::cpvar_to_state;

        while ( my ( $uapi, $cpvar ) = each %uapi_to_cpvar ) {
            next if !exists $metadata_hr->{$uapi};
            $Cpanel::CPVAR{$cpvar} = $metadata_hr->{$uapi};
        }
    }

    $api2_state_hr->{$api2_state_key} = {
        records_before_filter => $result->metadata('records_before_filter'),
        filtered              => [ map { _uapi_filter_to_api2($_) } @{ $result->finished_filters() } ],
        sorted                => [ map { _uapi_sort_to_api2($_) } @{ $result->finished_sorts() } ],
        paginated             => $pagination_obj ? 1 : 0,
    };

    return;
}

#The format that Cpanel::Api2::Filter::get_filters() returns.
sub _uapi_filter_to_api2 {
    my ($filter) = @_;

    return [ map { $filter->$_() } qw( column  type  term ) ];
}

#The format that Cpanel::Api2::Sort::get_sort_func_list() expects.
sub _uapi_sort_to_api2 {
    my ($sort) = @_;

    return { map { ( $_ => $sort->$_() ) } qw( method  reverse  column ) };
}

my $locale;

sub _locale {
    require Cpanel::Locale;
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

sub run_api_mode {
    my ($form) = @_;

    ## note: the correct spelling of 'suppress' is now supported
    $Cpanel::Carp::OUTPUT_FORMAT = 'suppress';
    ## UAPI note: the &execute method takes care of $Modify='none'
    local $Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT = 'plain';
    _locale()->set_context_plain() if _is_locale_initialized();

    my $module   = delete $form->{'api.module'};
    my $function = delete $form->{'api.function'};
    ## UAPI: as noted in cpsrvd, default output format is JSON
    my $output = delete $form->{'api.output'} || 'json';

    if ( $output eq 'xml' ) {
        my $api_call = "${module}::${function} (UAPI)";
        my $referer  = $ENV{'HTTP_REFERER'} =~ s{/cpsess(\d+)/}{/}r;
        Cpanel::Debug::log_deprecated("The XML API serialization is deprecated. API call $api_call; Referer '$referer'");
    }

    return print _serialize_result( execute( $module, $function, $form ), $output );
}

sub _serialize_result {
    my ( $result, $output ) = @_;

    my $public_result = $result->for_public();

    ## confirmed the two dependent functions do the right thing in regards to escaping/encoding
    my $serialized_data = (
        $output eq 'json'
        ? Cpanel::JSON::Dump($public_result)
        : ( "<?xml version=\"1.0\" ?>\n" . XMLout( $public_result, 'NoAttr' => 1, 'RootName' => 'result' ) )
    );
    if ( $output ne 'json' ) {
        $serialized_data =~ s/[\s\r\n]+$//g;
    }
    return $serialized_data . "\n";
}

sub _function_is_safe {
    return ( length( $_[0] ) > 1024 || substr( $_[0], 0, 1 ) eq '_' || $_[0] =~ tr{a-zA-Z0-9_}{}c ) ? 0 : 1;
}

sub clear_cache {
    %function_cache = ();
    return;
}

sub XMLout {
    Cpanel::LoadModule::load_perl_module('XML::Simple');
    $XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl";
    BEGIN { ${^WARNING_BITS} = ''; }    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
    *XMLout = *XML::Simple::XMLout;
    goto \&XML::Simple::XMLout;
}

sub _log_api_usage {
    my ( $module, $func ) = @_;

    my $call = {
        'call' => "${module}::${func}",
    };
    $call->{'page'}        = $ENV{'SCRIPT_FILENAME'} if defined $ENV{'SCRIPT_FILENAME'};
    $call->{'uri'}         = $ENV{'SCRIPT_URI'}      if defined $ENV{'SCRIPT_URI'};
    $call->{'api_version'} = 'uapi';

    require Cpanel::AdminBin::Call;
    Cpanel::AdminBin::Call::call( 'Cpanel', 'api_call', 'LOG', $call );

    return 1;
}

sub _safety_check_args {
    my ( $args, $result, $module, $function ) = @_;

    if ( Cpanel::JSONAPI::is_json_request() ) {
        my $args_hr = $args->get_raw_args_hr;

        my $full_module = 'Cpanel::API::' . $module;

        my $requires_json;
        do {
            no strict 'refs';
            my $api_hash = \%{ $full_module . "::API" };
            if ( ref $api_hash eq 'HASH' && ref $api_hash->{$function} eq 'HASH' ) {
                $requires_json = $api_hash->{$function}{requires_json};
            }
        };

        if ( !$requires_json && Cpanel::JSONAPI::has_nested_structures($args_hr) ) {
            $result->error( '[_1] does not expect nested data structures.', "${module}::$function" );
            $result->status(0);
        }
    }

    return;
}

sub _is_sandbox {
    return -e '/var/cpanel/dev_sandbox';
}

sub _is_locale_initialized {
    return ( scalar keys %Cpanel::Grapheme ) ? 1 : 0;
}

1;
