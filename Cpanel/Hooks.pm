package Cpanel::Hooks;

# cpanel - Cpanel/Hooks.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug      ();
use Cpanel::LoadModule ();

our $HOOKS_DB_DIR = '/var/cpanel/hooks';

my $debughooks;
my $MIN_SIZE_FOR_YAML_TO_HAVE_DATA = 6;

our %loaded;

=head1 NAME

Cpanel::Hooks

=head1 SYNOPSIS

    # Hook an event:
    Cpanel::Hooks::hook({
        'category' => 'Cpanel',
        'event'    => 'API12::do_the_dew',
        'stage'    => 'pre',
        'blocking' => 1,
    });

    # Load Hook data for an event:
    my $hook_ar = Cpanel::Hooks::load_hooks_for( 'Cpanel', 'API2::do_the_dew' );

=head1 DESCRIPTION

This module is intended to do all the things necessary to *load* and *execute*
hooks within the "Standardized Hooks System" for cPanel and WHM. Management
of hooks (add, edit, delete, etc.) is done in Cpanel::Hooks::Manage.

For context, realize that the structure of "Standardized Hooks" looks like so
on the filesystem:

    /var/cpanel/hooks/data/
    |_Category1
      |_Event1.yaml
      |_Event2.yaml
      |_...
    |_Category2
    |_...

Where each YAML file represents "What hooks are registered for this event"
and any associated configuration needed to properly execute the hook.
Each hook *entry* for an event will look something like this:

    {
      exectype => 'module', # What kind of thing we run -- subroutine or script
      hook     => 'CCSHooks::admin_domainremove', # What to run
      id       => '7cmIbICHN7nWvWyBY_BbDEje', # Used in APIs to search for it
      stage    => 'post', # When to execute -- pre or post event?
      weight   => 100, # When other events exist for this stage, what order
                       # should we execute in (low to high)?
    }

Please see our public documentation for "Standardized Hooks" on
https://api.docs.cpanel.net for full coverage on other possible values
that are valid in hook entries and what those all do.

=head1 SUBROUTINES

=head2 is_name_invalid

Does the category or event name look invalid?
Accepts STRING passed in, returns whether it looks invalid.

=cut

# Only here so I don't have to continually update this in multiple places.
sub is_name_invalid {
    return $_[0] =~ tr{a-zA-Z0-9:_}{}c;
}

=head2 load_hooks_for ( $category, $event, $options_hr )

Loads hooks for the specified $event within the specified $category.
Optionally accepts $options_hr HASHREF which allows a few things:

    'skip_file_check' => 1, # BOOL-like var, allows you to save a stat on
                            # the event yaml file if you've already done
                            # size checking on the file beforehand.
    'filter_id'       => 'string' , # Identifier to filter by. If you
                                    # want multiple, pass ARRAYREF

Returns ARRAYREF of HASHREFs (if any entries are registered for the event).

=cut

# NOTE -- all in memory caching is done by Cpanel::CachedDataStore already.
# We duplicate *some* of this in the %loaded hash, but thankfully it is only
# storing a ref to the arrayref loaded by CachedDataStore.

# Returns ARRAYREF of hook entry data HASHREFs.
sub load_hooks_for {
    my ( $category, $event, $options_hr ) = @_;
    $options_hr = {} if ( !$options_hr || ref $options_hr ne 'HASH' );

    # Since this is our entry point, may as well get the debug hooks value if
    # it is not already set in this execution context.
    $debughooks = Cpanel::Debug::debug_hooks_value() if !defined($debughooks);

    # Category & Event names are subject to these limitations:
    # * Must translate to a 'shallow' path component (no '/' char)
    # * Must be an ASCII character within the set of alphanumeric characters
    #   along with the '_' or ':' characters.
    # * Must not exceed PATH_MAX for your system when concatenated together as
    #   /var/cpanel/hooks/data/${CATEGORY}/${EVENT}.yaml (see limits.h)
    # Note that the last requirement will simply fail on file checks, etc. or
    # load, not the conditional below.
    return [] if ( !$category || !$event || grep { is_name_invalid($_) } ( $category, $event ) );

    # Return shallow clone of the cache if it exists already
    if ( ref $loaded{$category} eq 'HASH' && ref $loaded{$category}->{$event} eq 'ARRAY' && scalar @{ $loaded{$category}->{$event} } ) {
        if ( $options_hr->{'filter_id'} ) {
            $options_hr->{'filter_id'} = [ $options_hr->{'filter_id'} ] if ref $options_hr->{'filter_id'} ne 'ARRAY';
            return [
                grep {
                    my $id = '';
                    $id = $_->{'id'} if ( ref $_ eq 'HASH' && $_->{'id'} );
                    grep { defined $_ && "$id" eq "$_" } @{ $options_hr->{'filter_id'} };
                } @{ $loaded{$category}->{$event} }
            ];
        }
        return [ @{ $loaded{$category}->{$event} } ];
    }

    my $hook_file = "$HOOKS_DB_DIR/data/$category/$event.yaml";

    # Do not allow path traversal via symlink or non-file entries to be loaded,
    # also make sure the size shows it has something worth loading
    return [] if ( -l $hook_file || !-f _ || ( -s _ || 0 ) < $MIN_SIZE_FOR_YAML_TO_HAVE_DATA );

    # Loading hooks should not be fatal, but at least warn about problems in log
    require Cpanel::CachedDataStore;
    local $@;
    my $hook_ar = eval { Cpanel::CachedDataStore::loaddatastore($hook_file) };
    Cpanel::Debug::log_warn($@) if $@;
    return []                   if !$hook_ar;

    # Our $loaded entry should have a ref to cacheddatastore's ref so that we
    # do not make an additional copy. That's why we dont' use load_ref above.
    $loaded{$category} ||= {};
    $loaded{$category}->{$event} = $hook_ar->{'data'};

    # Only return the ID if that is the ask here.
    # Also ensure the id is coerced to be string to avoid warns.
    # a "top level" clone is returned so that the caller can't accidentally
    # break things.
    if ( $options_hr->{'filter_id'} ) {
        $options_hr->{'filter_id'} = [ $options_hr->{'filter_id'} ] if ref $options_hr->{'filter_id'} ne 'ARRAY';
        return [
            grep {
                my $id = '';
                $id = $_->{'id'} if ( ref $_ eq 'HASH' && $_->{'id'} );
                grep { defined $_ && "$id" eq "$_" } @{ $options_hr->{'filter_id'} };
            } @{ $hook_ar->{'data'} }
        ];
    }
    return [ @{ $hook_ar->{'data'} } ];
}

=head2 hooks_exist_for_category ( $category )

Returns 1 or 0 depending on whether or not hooks exist for the specified
$category.

=cut

sub hooks_exist_for_category {
    my ($category) = @_;
    return   if ( !$category || is_name_invalid($category) );
    return 1 if exists( $loaded{$category} );
    my $dir2search = "$HOOKS_DB_DIR/data/$category";

    return scalar(
        scandir(
            'dir'    => $dir2search,
            'first'  => 1,
            'wanted' => sub {
                my ($entry) = @_;

                # Only care about YAML files that have data here
                return if ( substr( $entry, -5 ) ne '.yaml' );
                return if ( ( -s "$dir2search/$entry" || 0 ) < $MIN_SIZE_FOR_YAML_TO_HAVE_DATA );
                return 1;
            }
        )
    );
}

# Note -- not using File::Find here due to not needing to search depth
# Opts:
# dir    -- Dir 2 scan
# wanted -- Coderef to run on the file name to see if it is what you want
# first  -- Return once you find the first thing to satisfy $wanted
# RETURNS: list
sub scandir {
    my %opts = @_;
    return () if !$opts{'dir'}      || !-d $opts{'dir'};
    opendir( my $dh, $opts{'dir'} ) || return ();

    my @found;
    foreach my $entry ( readdir($dh) ) {

        # Exclude entries like . & .. or hidden files
        next if index( $entry, '.' ) == 0;

        if ( $opts{'wanted'}->($entry) ) {
            push @found, $entry;
            return @found if $opts{'first'};
        }
    }
    return @found;
}

=head2 hook ( $context )

Executes whatever hooks are registered for a given hook $context HASHREF,
passing along any relevant $data (mixed, possibly HASHREF or ARRAYREF) to the
hook action script or subroutine.
Returns LIST of whether the hooks matching the $context all executed
successfully (1 or 0) and any associated messages (ARRAYREF) relating to the
run. Typically the caller is expected to consult messages when the hook
execution return indicates a failure.

=cut

sub hook {
    my ( $context, $data ) = @_;
    $data ||= [];

    # Make a copy of the data with all the code references removed
    $data = _filter_data($data);

    # TODO Needs to return success if no hook data in context
    my @ran_hooks;
    my @msgs;

    my @hooks2run = _get_hooks_list($context);

    # Must always return status and arrayref of messages.
    # In this case, indicate success, as nothing needed doing.
    return ( 1, [] ) if !@hooks2run;

    if ( ref $data eq "HASH" ) {
        delete @{$data}{ grep { tr/\r\n\0// } keys %$data };
    }

    foreach my $hook (@hooks2run) {
        next if $hook->{'stage'} ne $context->{'stage'};
        if ( defined $hook->{'disabled'} && $hook->{'disabled'} ) {
            _debug( 'Hook found, but is disabled', undef, $hook, $context ) if $debughooks == 3;
            next;
        }

        my $check_result = 1;
        my $msg;
        my $exec_result = 1;
        eval {
            if ( exists $hook->{'check'} ) {
                ( $check_result, $msg ) = _exec_hook( 'check', $hook, $context, $data );
                next if !$check_result;
            }
            ( $exec_result, $msg ) = _exec_hook( 'main', $hook, $context, $data );
            push @msgs,      $msg  if defined $msg;
            push @ran_hooks, $hook if $exec_result;
        };
        if ( my $err = $@ ) {
            require Cpanel::Exception;
            push @msgs, Cpanel::Exception::get_string($err);
            if ( $err =~ /BAILOUT/ ) {
                Cpanel::Debug::log_warn("An exception was thrown in the hook “$hook->{'hook'}” for “$context->{'category'}::$context->{'event'}”: $msgs[-1]");
                if ( $hook->{'blocking'} || $context->{'blocking'} ) {
                    _exec_rollback( $hook, $context, $data, \@ran_hooks );
                    return 0, \@msgs;
                }
                next;
            }
        }
        if ( ( $hook->{'blocking'} || $context->{'blocking'} ) && !$exec_result ) {
            _exec_rollback( $hook, $context, $data, \@ran_hooks );
            return 0, \@msgs;
        }
    }
    return 1, \@msgs;
}

# Do we want to care about the return value from the rollback loop, only use I can see is an error message.
sub _exec_rollback {
    my ( $hooks, $context, $data, $ran_hooks ) = @_;
    foreach my $hook ( @{$ran_hooks} ) {
        next if !exists $hook->{'rollback'};
        my ($result) = _exec_hook( 'rollback', $hook, $context, $data );
        Cpanel::Debug::log_info( 'rollback hook ' . $hooks->{'rollback'} . ' for ' . $hook->{'hook'} . ' in context ' . $context->{'category'} . '::' . $context->{'event'} . ' returned a non-true status (this may indicate failure)' ) if !$result;
    }
    return 1;
}

sub _get_hooks_list {
    my ($context) = @_;
    return () if ref $context ne 'HASH';

    my ( $category, $event ) = @{$context}{qw( category  event )};
    return () unless $event && $category;

    my $contextual_hook_list;
    {

        # If it fails in this context, just assume there are no hooks
        local $@;
        $contextual_hook_list = eval { load_hooks_for( $category, $event ) };
    }
    if ( ref $contextual_hook_list eq 'ARRAY' ) {
        if ( $debughooks == 3 ) {
            my $hook_list_contains_context_stage = 0;
            foreach my $hook (@$contextual_hook_list) {
                $hook_list_contains_context_stage++ if $hook->{'stage'} eq $context->{'stage'};
            }
            _debug( "No hooks found for '$context->{'stage'}' stage of context", undef, undef, $context ) if $hook_list_contains_context_stage < 1;
        }
        return @$contextual_hook_list;
    }

    #In case people twiddle with the .yaml file manually...
    elsif ($contextual_hook_list) {
        Cpanel::Debug::log_warn("Malformed hook list $category:$event - must be an array");
    }

    _debug( 'No hooks found for traversed context', undef, undef, $context ) if $debughooks == 3;
    return ();
}

# Copy the data while removing the code references
sub _filter_data {
    my ($data) = @_;

    if ( ref $data eq 'CODE' ) {
        return '<coderef>';
    }
    elsif ( ref $data eq 'ARRAY' ) {
        my @copy = map { _filter_data($_) } @$data;
        return \@copy;
    }
    elsif ( ref $data eq 'HASH' ) {
        my %copy = map { $_ => _filter_data( $data->{$_} ) } keys %$data;
        return \%copy;
    }

    return $data;
}

sub _exec_hook {
    my ( $point, $hook, $context, $data ) = @_;
    my $result = 1;
    my $msg    = undef;
    $context->{'point'} = $point;
    if ( $hook->{'exectype'} eq 'script' ) {
        _debug( 'Beginning execution of script hook.', $point, $hook, $context, $data ) if $debughooks;
        ( $result, $msg ) = _exec_script( $point, $hook, $context, $data );
        _debug( 'Finished execution of script hook.', $point, $hook, $context, $data, $result ) if $debughooks;
    }
    elsif ( $hook->{'exectype'} eq 'module' ) {
        _debug( 'Beginning execution of module hook.', $point, $hook, $context, $data ) if $debughooks;
        ( $result, $msg ) = _exec_module( $point, $hook, $context, $data );
        _debug( 'Finished execution of module hook.', $point, $hook, $context, $data, $result ) if $debughooks;
    }
    else {
        Cpanel::Debug::log_warn( 'invalid hook type called for ' . $context->{'category'} . "::" . $context->{'event'} );
    }
    return $result, $msg;
}

sub _debug {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $msg, $point, $hook, $context, $data, $result ) = @_;
    $hook    ||= '';
    $context ||= {};
    $data    ||= [];
    $result //= 0;
    return if !$debughooks;
    Cpanel::Debug::log_info('---debug_hooks---');
    Cpanel::Debug::log_info( '            msg: ' . $msg );
    Cpanel::Debug::log_info( '        context: ' . $context->{'category'} . '::' . $context->{'event'} );
    Cpanel::Debug::log_info( '          stage: ' . $context->{'stage'} );
    Cpanel::Debug::log_info( '         result: ' . $result ) if defined $result;
    Cpanel::Debug::log_info( '          point: ' . $point )  if defined $point;

    if ( defined $hook && ref $hook eq 'HASH' ) {
        Cpanel::Debug::log_info( '             id: ' . $hook->{'id'} )            if exists $hook->{'id'};
        Cpanel::Debug::log_info( '           hook: ' . $hook->{'hook'} )          if exists $hook->{'hook'};
        Cpanel::Debug::log_info( '  escalateprivs: ' . $hook->{'escalateprivs'} ) if exists $hook->{'escalateprivs'};
        Cpanel::Debug::log_info( '         weight: ' . $hook->{'weight'} )        if exists $hook->{'weight'};
        Cpanel::Debug::log_info( '       rollback: ' . $hook->{'rollback'} )      if exists $hook->{'rollback'};
        Cpanel::Debug::log_info( '          check: ' . $hook->{'check'} )         if exists $hook->{'check'};
    }
    if ( $debughooks > 1 && defined $data ) {
        require Cpanel::JSON;
        my $json_dump = "Error in JSON dump :";
        eval { $json_dump = Cpanel::JSON::Dump($data); };
        if ($@) {
            $json_dump .= "\n\t$@";
        }
        Cpanel::Debug::log_info( '           data: ' . $json_dump );
    }
    return;
}

=head2 set_debug ( $level )

Sets the "Hooks debug level" to the specified value. Valid values are in the
range of 0-3:

    0 => Suppress debugging output.
    1 => Emit debugging info when hook() executes registered entries for
         whatever context it currently is evaluating.
    2 => Same as 1, but also emits this data to
         /usr/local/cpanel/logs/error_log.
    3 => Same as 2, except that it logs hook context execution even when
         no registered hook action entries exist for the given hook action
         context.

Returns the passed in $level.

=cut

sub set_debug {
    return ( $debughooks = $_[0] );
}

sub _exec_script {    ## no critic qw(ProhibitExcessComplexity) # Would rather not introduce more bugs via refactor
    my ( $point, $hook, $context, $data ) = @_;
    my ( $script, @script_args );

    my $hook_name = $point eq 'main' ? 'hook' : $point;
    if ( $point eq 'main' || $point eq 'check' || $point eq 'rollback' ) {
        ( $script, @script_args ) = split( /\s/, $hook->{$hook_name} );
    }
    else {
        Cpanel::Debug::log_warn( 'exec_script was called with an invalid execution point of ' . $point );
        return 0;
    }

    my $input = {
        'hook'    => $hook,
        'context' => $context,
        'data'    => $data,
    };

    my ( $output, $msg );

    if ( $script eq '/usr/local/cpanel/scripts/run_if_exists' && !-e $script_args[0] ) {

        # Avoid SIGPIPE since run_if_exists will not consume STDIN
        return 1;
    }

    # TODO: refactor escalation scripts to be aware of 'points'
    if ( $hook->{'escalateprivs'} && $< != 0 ) {
        if ( $context->{'escalateprivs'} ) {

            # NOTE -- DO NOT TURN THIS INTO A REQUIRE!
            # If you do, updatenow.static will try to load IO::FDPass, which
            # leads to install failures due to it not existing at this point
            # in time.
            Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
            require Cpanel::JSON;
            $output = Cpanel::AdminBin::adminstor( 'hooks2', $context->{'category'} . "::" . $context->{'event'}, $input );

            # Chances are if it isn't json, it is an error message.
            # Print that instead if it is truthy.
            local $@;
            my $decoded = eval { Cpanel::JSON::Load($output) };
            die( $output || $@ ) if $@;
            $output = $decoded;
        }
        else {
            $msg = 'A script hook attempted to escalate privileges when escalation was not permitted in ' . $context->{'category'} . '::' . $context->{'event'} . ' with the script ' . $script;
            Cpanel::Debug::log_info($msg);
            return 0, $msg;
        }
    }
    else {
        require Cpanel::JSON;
        require Cpanel::SafeRun::Full;
        $output = Cpanel::SafeRun::Full::run(
            'program' => $script,
            'stdin'   => Cpanel::JSON::Dump($input),
            'args'    => \@script_args,
        );
    }
    if ( exists $output->{'message'} && $output->{'message'} !~ /Executed / ) {
        Cpanel::Debug::log_warn( $output->{'message'} );
    }
    if ($debughooks) {
        if ( $output->{'stdout'} ne '' ) {
            Cpanel::Debug::log_info( 'STDOUT output from hook: ' . $hook->{'hook'} );
            Cpanel::Debug::log_info( $output->{'stdout'} );
            Cpanel::Debug::log_info('End STDOUT from hook');
        }
        else {
            Cpanel::Debug::log_info( 'HOOK INFO: hook ' . $hook->{'hook'} . ' did not output any data' );
        }
    }

    # Print STDERR from the hook directly to the error_log
    if ( exists $output->{'stderr'} && $output->{'stderr'} ne '' ) {
        Cpanel::Debug::log_info( 'STDERR output from hook: ' . $hook->{'hook'} );
        Cpanel::Debug::log_info( $output->{'stderr'} );
        Cpanel::Debug::log_info('End STDERR from hook');
    }
    return 1                   if !exists $output->{'stdout'} || $output->{'stdout'} eq '';
    return $output->{'stdout'} if $output->{'stdout'} eq '0'  || $output->{'stdout'} eq '1';
    my $result;
    ( $result, $msg ) = split( ' ', $output->{'stdout'}, 2 );
    if ( $result eq 'BAILOUT' && $point ne 'rollback' ) {
        die "BAILOUT The hook has thrown an exception indicating that it should be halted. " . $msg;
    }
    if ( $result ne 'BAILOUT' && $result ne '0' && $result ne '1' ) {
        Cpanel::Debug::log_info('Script hook returned an invalid response: ');
        Cpanel::Debug::log_info( '   script: ' . $hook->{'hook'} );
        Cpanel::Debug::log_info( ' response: ' . $output->{'stdout'} );
        Cpanel::Debug::log_info(' -- End Garbage output -- ');
    }
    return $result, $msg;
}

sub _exec_module {
    my ( $point, $hook, $context, $data ) = @_;
    my ( $module, $subroutine );

    my $hook_name = $point eq 'main' ? 'hook' : $point;
    if ( $point eq 'main' || $point eq 'check' || $point eq 'rollback' ) {
        ( $module, $subroutine ) = $hook->{$hook_name} =~ /(^[a-zA-Z0-9\:_]+)\:\:([a-zA-Z0-9_]+)$/;
    }
    else {
        Cpanel::Debug::log_warn( 'exec_module was called with an invalid execution point of ' . $point );
        return 0;
    }

    local @INC = ( @INC, '/var/cpanel/perl5/lib' );
    return 1 if !defined $module || !defined $subroutine;
    eval "require $module;";    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)

    if ($@) {
        Cpanel::Debug::log_warn($@);
        return 1;
    }
    my $return = 1;
    my $msg    = undef;
    eval {
        if ( my $cr = $module->can($subroutine) ) {
            ( $return, $msg ) = $cr->( $context, $data );
        }
        else {
            Cpanel::Debug::log_warn("Could not find $subroutine in module $module");
        }
    };
    if ( $@ =~ /BAILOUT/ && $point ne 'rollback' ) {
        die $@;
    }
    Cpanel::Debug::log_warn($@) if $@;
    return $return, $msg;
}

=head2 hook_halted_msg ( $hook_info, $hook_msg )

Formats the given $hook_msg in such a manner to indicate that the $hook_info
context provided was halted.
Returns ARRAYREF of messages or SCALAR string of the formatted message.

=cut

sub hook_halted_msg {
    my ( $hook_info, $hook_msgs ) = @_;

    # The_hook_abides is a safety catch in the event a hook is created or used in a way that doesn't pass
    # in the constructor args used for creating the hook for a better error message.
    # If it abides by the "send the constructor ref along with output from hook script/module" idea, we can
    # show our useful error, otherwise we can only show the generic "some hook did this" message with output

    my $the_hook_abides  = 0;
    my $hook_error_descr = "A hook has halted this operation.\n";
    if ( ref($hook_info) eq 'HASH' ) {
        if ( $hook_info->{'category'} ) {
            $hook_error_descr .= "Category : $hook_info->{'category'}\n";
            $the_hook_abides = 1;
        }
        if ( $hook_info->{'event'} ) {
            $hook_error_descr .= "Event : $hook_info->{'event'}\n";
            $the_hook_abides = 1;
        }
        if ( $hook_info->{'stage'} ) {
            $hook_error_descr .= "Stage : $hook_info->{'stage'}\n";
            $the_hook_abides = 1;
        }
    }

    if ( $the_hook_abides != 1 ) {
        $hook_msgs = $hook_info;
    }

    if ($hook_msgs) {
        if ( ref($hook_msgs) eq 'ARRAY' && @{$hook_msgs} ) {
            return $hook_error_descr . join( "\n", @{$hook_msgs} );
        }
        elsif ( !ref($hook_msgs) && $hook_msgs ) {
            return $hook_error_descr . $hook_msgs;
        }
    }

    return $hook_error_descr;
}

1;
