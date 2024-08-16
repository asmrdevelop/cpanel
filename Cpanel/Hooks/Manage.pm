package Cpanel::Hooks::Manage;

# cpanel - Cpanel/Hooks/Manage.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use lib '/var/cpanel/perl5/lib';

use Cwd                     ();
use Cpanel::Hooks           ();
use Cpanel::Hooks::Metadata ();

our $ERRORMSG = '';
our $all_loaded;
our $SCRIPTS_RUN_IF_EXISTS = '/usr/local/cpanel/scripts/run_if_exists';

my $MIN_SIZE_FOR_YAML_TO_HAVE_DATA = 6;

=head1 NAME

Cpanel::Hooks::Manage

=head1 SYNOPSIS

    # Add a hook:
    my %context = (
        'category'      => 'Cpanel',
        'event'         => 'API12::do_the_dew',
        'stage'         => 'pre',
        'blocking'      => 1,
        'exectype'      => 'script',
        'hook'          => '/scripts/fixeverything',
        'escalateprivs' => 1, # Will cause an exception when exectype=module
        'rollback'      => '/scripts/always_low_prices',
        'check'         => '/bin/true',
    );
    my $result = Cpanel::Hooks::Manage::add(%context);

    # Note, 'add' does not return the event's ID currently.
    ... # See Cpanel::Hooks for how to retrieve your hook entry id

    # Edit:
    Cpanel::Hooks::Manage::edit_hook( $id, %context);

    # Delete:
    Cpanel::Hooks::Manage::delete($context);

    # Prune no longer existing hooks:
    Cpanel::Hooks::Manage::prune();

=head1 DESCRIPTION

This module is intended to do all the things necessary to *add/edit/delete*
hooks or otherwise manage the hooks "database". Some getters exist here,
but mostly to massage the data into a form either our APIs or UI wants.

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

=head2 add ( %OPTS )

Adds hook event to the category and event matching the provided %OPTS.
Returns undef on failure, 'OK' on success and 'SKIPPED' if it is already
registered.

Use edit() if you want to update a hook, not add().

=cut

sub add {
    my %OPTS = @_;
    _change_legacy_opts( \%OPTS );

    # perform various checks to ensure that the hook being added is sane
    if ( my @missing = grep { !defined $OPTS{$_} } qw{hook event exectype category stage} ) {
        $ERRORMSG = "Adding a hook requires that hook, event, exectype, stage and category are defined.\n    Missing: " . join( ', ', @missing );
        return;
    }

    if ( $OPTS{'exectype'} ne 'module' && $OPTS{'exectype'} ne 'script' ) {
        $ERRORMSG = 'The only two valid exectypes are "script" and "module"';
        return;
    }

    # Check if the module/script we're to execute looks OK
    if ( $OPTS{'exectype'} eq 'module' ) {
        if ( defined $OPTS{'escalateprivs'} && $OPTS{'escalateprivs'} == 1 ) {
            $ERRORMSG = 'Module hooks cannot escalate privileges';
            return;
        }

        foreach my $key (qw{hook rollback check}) {
            next if !exists $OPTS{$key};
            my ( $module, $subroutine ) = $OPTS{$key} =~ /(^[a-zA-Z0-9_\:]+)\:\:([a-zA-Z0-9_]+)$/;
            my $check = _module_hook_is_usable( $module, $subroutine );
            if ( $check ne 'OK' ) {
                $ERRORMSG = $check;
                return;
            }
        }
    }
    else {    # It is a script
        $OPTS{'escalateprivs'} = 0 if !defined $OPTS{'escalateprivs'};

        # Get the absolute paths: remove any potential symbolic links, resolve
        # path issues, etc. Expunge any provided cli switches for that script
        foreach my $key (qw(hook rollback check)) {
            next if !exists $OPTS{$key};
            my ($script) = split( /\s/, $OPTS{$key}, 2 );
            my $ABS_PATH = Cwd::abs_path($script);
            if ( !$OPTS{'force'} && ( !$ABS_PATH || !-x $ABS_PATH ) ) {
                $ERRORMSG = "The provided script $key ($script) is not executable";
                return;
            }
        }
    }

    my ( $category, $event ) = delete @OPTS{ 'category', 'event', 'force' }, my $hook_ref = \%OPTS;
    my $hook_db = Cpanel::Hooks::load_hooks_for( $category, $event );

    # Don't add duplicate hooks, but it isn't an error.
    if ( $OPTS{'exectype'} eq 'script' ) {

        # Normalize the paths of existing and new hook scripts when checking for a match to prevent duplicates via symlink.
        my $normalized_hook = _normalize_hook_script_path( $OPTS{'hook'} );
        if ( grep { $_->{'stage'} eq $OPTS{'stage'} && _normalize_hook_script_path( $_->{'hook'} ) eq $normalized_hook } @$hook_db ) {
            return "SKIPPED";
        }
    }
    elsif ( grep { $_->{'stage'} eq $OPTS{'stage'} && $_->{'hook'} eq $OPTS{'hook'} } @$hook_db ) {
        return "SKIPPED";
    }

    if ( defined $OPTS{'weight'} ) {
        if ( $OPTS{'weight'} !~ /^[0-9]+$/ ) {
            $ERRORMSG = 'The weight must be a number.';
            return;
        }
        $OPTS{'weight'} = int $OPTS{'weight'};
    }
    elsif (@$hook_db) {
        $OPTS{'weight'} = $hook_db->[-1]->{'weight'} + 100;
    }
    else {
        $OPTS{'weight'} = 100;
    }

    if ( defined $OPTS{'escalateprivs'} ) {
        if ( $OPTS{'escalateprivs'} !~ /^[01]$/ ) {
            $ERRORMSG = 'escalateprivs must be set to either a 0 or a 1.';
            return;
        }
        $OPTS{'escalateprivs'} = int $OPTS{'escalateprivs'};
    }

    require Cpanel::UUID;
    $hook_ref->{'id'} = Cpanel::UUID::random_uuid();
    push( @$hook_db, $hook_ref );
    $hook_db = [ sort { int $a->{'weight'} <=> int $b->{'weight'} } @$hook_db ];

    save_hooksdb( $category, $event, $hook_db );
    $ERRORMSG = '';
    return 'OK';
}

sub _module_hook_is_usable {
    my ( $module, $subroutine ) = @_;
    eval " require $module ";    ## no critic qw(ProhibitStringyEval);
    if ($@) {
        return "Attempting to load the specified module $module returned an error:\n$@";
    }

    my $res = 0;
    eval { $res = $module->can($subroutine) };
    if ( ref $res ne 'CODE' ) {
        return "The hook subroutine $subroutine does not exist in $module";
    }
    return 'OK';
}

# Normalizes first two items in the hook command line when using scripts/run_if_exists, otherwise only the first item.
sub _normalize_hook_script_path {
    my ($hook) = @_;
    my @items = split( /\s+/, $hook );     # Collapse extra whitespace

    for my $item (@items) {
        if ( index( $item, q{/} ) == 0 ) {    # Ensure path begins with / to prevent Cwd::abs_path prepending the Current Working Directory
            $item = Cwd::abs_path($item) // $item;    # Leave unmodified if abs_path returns undef
        }
        last if $item ne $SCRIPTS_RUN_IF_EXISTS;
    }
    return join( q{ }, @items );
}

=head2 delete ( %OPTS )

Deletes hook event from the category and event matching the provided %OPTS.
Returns undef on failure, 1 on success. Unlinks the event's associated YAML
file & cache file if no entries exist anymore for the event.

=cut

sub delete {
    my %OPTS = @_;
    _change_legacy_opts( \%OPTS );
    my ( $event, $category ) = delete @OPTS{ 'event', 'category' };

    # these attributes are able to be edited through the UI so what's in a
    # hook's describe method may not match reality here. As such these should
    # never be used as criteria for deletion.
    delete @OPTS{ 'weight', 'disabled' };

    my $hook_ref;

    if ( $category && $event && $OPTS{'hook'} ) {
        $hook_ref = Cpanel::Hooks::load_hooks_for( $category, $event );
        if ( !scalar(@$hook_ref) ) {
            $ERRORMSG = "Provided event of \'$event\' in category \'$category\' does not exist in hooks registry or is malformed. (this may indicate that the specified hook is not installed)";
            return;
        }
    }

    elsif ( $OPTS{'id'} ) {

        # In this case, the entire list of hooks must be searched through to
        # find the target hook. On top of this, the entire set for that hook's
        # category and event must be loaded so that the target can be removed
        # and the rest saved back.
        my @hook_list = Cpanel::Hooks::Manage::get_hooks_list( 'id' => $OPTS{'id'} );
        if ( !scalar(@hook_list) ) {
            $ERRORMSG = "Provided ID \'$OPTS{'id'}\' does not exist in hooks registry or is malformed. (this may indicate that the specified hook is not installed)";
            return;
        }
        elsif ( scalar(@hook_list) > 1 ) {

            # We found multiple hooks with the same ID. This shouldn't have happened.
            # But if it does, though, warn and proceed using the first hook in the list.
            require Cpanel::Logger;
            Cpanel::Logger->new()->warn("Multiple hooks found with ID \'$OPTS{'id'}\'! Using the first one found.");
        }

        ( $category, $event ) = $hook_list[0]->@{ 'category', 'event' };
        $hook_ref = Cpanel::Hooks::load_hooks_for( $category, $event );

        # $hook_ref should not be empty, or the function wouldn't still be
        # running here due to the previous conditional. If that's not true,
        # something is very, *very* wrong, and aborting immediately seems
        # like a reasonable thing to do.
        if ( !scalar(@$hook_ref) ) {
            die "Hook with ID \'$OPTS{'id'}\' indicated that it covered event of \'$event\' in category \'$category\', but no hooks were found there. Please contact cPanel support for further assistance.";
        }
    }

    else {
        $ERRORMSG = 'Deleting a hook requires that an id or a category, a event and a hook are passed as parameters';
        return;
    }

    # Delete the hook
    my $deleted;
    for ( my $i = 0; $i <= $#{$hook_ref}; $i++ ) {
        if ( _cmp_hooks( $hook_ref->[$i], \%OPTS ) ) {
            $deleted = splice( @$hook_ref, $i, 1 );
            last;
        }
    }
    if ( !$deleted ) {
        $ERRORMSG = "No matching hooks found for '${event}' in category '${category}'";
        return;
    }

    save_hooksdb( $category, $event, $hook_ref );
    $ERRORMSG = '';
    return 1;
}

sub _check_entry {
    my ( $category, $event, $entry ) = @_;
    if (
           !$category
        || !$event
        || ref $entry ne 'HASH'
        || ref $entry->{$category} ne 'HASH'
        || ref $entry->{$category}{$event} ne 'ARRAY'
        || !grep {
            my $key = $_;
            grep { ref $_ eq 'HASH' && exists $_->{$key} } @{ $entry->{$category}{$event} }
        } qw{exectype id hook stage weight}
    ) {
        $ERRORMSG = "Provided event of \'$event\' in category \'$category\' does not exist in hooks registry or is malformed. (this may indicate that the specified hook is not installed)";
        return;
    }
    return 1;
}

=head2 get_hooks_list

Returns a 'flat' version of Cpanel::Hooks::load_all_hooks as an ARRAYREF of
HASHREFs. Be wary of changing the return structure here, as this is used
to construct the WHM API 1 list_hooks return.

Accepts a list of %filter_args which are passed on to load_all_hooks verbatim.

=cut

sub get_hooks_list {
    my %filter_args = @_;
    my @hooks_array;

    my $hooksdb = load_all_hooks(%filter_args);
    foreach my $category ( keys %{$hooksdb} ) {
        foreach my $event ( keys %{ $hooksdb->{$category} } ) {
            foreach my $hook ( @{ $hooksdb->{$category}{$event} } ) {
                $hook->{'category'} = $category;
                $hook->{'event'}    = $event;

                $hook->{'escalateprivs'} = 0 if !exists $hook->{'escalateprivs'};

                push @hooks_array, $hook;
            }
        }
    }

    return @hooks_array;
}

=head2 get_structured_hooks_list

Returns an 'augmented' version of Cpanel::Hooks::load_all_hooks using data
taken from Cpanel::Hooks::Metadata. Be wary of changing the return structure
here, as this is used to construct the WHM >> Manage Hooks interface.

Example:

    {
        'Category1' => {
            'Event1' => [
                {
                    'exectype'    => 'script',
                    'hook'        => /scripts/arrrrrrrrrrrrr'
                    'description' => 'This hook makes you talk like a pirate.',
                    ...,
                },
            ],
            ...,
        },
        ...,
    }

=cut

sub get_structured_hooks_list {
    my $res = [];

    my $hooksdb = load_all_hooks();
    foreach my $category ( sort keys %{$hooksdb} ) {
        my $category_hr = {
            'category' => $category,
            'events'   => [],
        };

        foreach my $event ( keys %{ $hooksdb->{$category} } ) {
            my $event_hr = {
                'event'       => $event,
                'stages'      => [],
                'stage_order' => [ Cpanel::Hooks::Metadata::get_stage_order( $category, $event ) ],
            };
            my $tmp_stage_hr = {};    # this one is a bit different on purpose, trust me on this.
            foreach my $action ( @{ $hooksdb->{$category}->{$event} } ) {
                @{$action}{ 'category', 'event' } = ( $category, $event );

                my $stage = $action->{'stage'};
                $tmp_stage_hr->{$stage} = [] if !exists $tmp_stage_hr->{$stage};

                # set all option int bool attrs to 0 to indicate their default value
                foreach my $optional_attr (qw { disabled escalateprivs }) {
                    $action->{$optional_attr} = 0 if !exists $action->{$optional_attr};
                }

                # set all optional string attributes to undef
                foreach my $optional_attr (qw { description rollback check }) {
                    $action->{$optional_attr} = undef if !exists $action->{$optional_attr};
                }

                #                $action->{'notes'} = delete $action->{'description'};

                my $stage_attributes = Cpanel::Hooks::Metadata::get_stage_attributes( $category, $event, $stage );
                if ( exists $stage_attributes->{'blocking'} && $stage_attributes->{'blocking'} ) {
                    $action->{'blocking'} = 1;
                }
                else {
                    $action->{'blocking'} = 0;
                }
                $action->{'enabled'} = $action->{'disabled'} ? 0 : 1;
                delete $action->{'disabled'};
                push @{ $tmp_stage_hr->{$stage} }, $action;
            }
            my @stage_ar;
            foreach my $stage ( Cpanel::Hooks::Metadata::get_stage_order( $category, $event ), sort keys %{$tmp_stage_hr} ) {
                next if !defined $tmp_stage_hr->{$stage};
                push @stage_ar,
                  {
                    'description' => Cpanel::Hooks::Metadata::get_stage_description( $category, $event, $stage ),
                    'actions'     => $tmp_stage_hr->{$stage},
                    'stage'       => $stage,
                    'attributes'  => Cpanel::Hooks::Metadata::get_stage_attributes( $category, $event, $stage ),
                  };
                delete $tmp_stage_hr->{$stage};
            }
            $event_hr->{'stages'} = \@stage_ar;
            push @{ $category_hr->{'events'} }, $event_hr;
        }
        push @{$res}, $category_hr;
    }
    return $res;
}

=head2 reorder_hooks (@ids)

Re-orders hooks for the given hook IDs in the order you pass them. Begins
at weight 100 and increments by 100 for each passed in ID.
Will return in failure if one of the IDs cannot be found, or if all of the
given IDs don't correspond to the same hook event and stage.
Returns ARRAYREF of the rearranged hook event entries.

Note that this is assuming that all IDs you pass in correspond to the same
category, event and stage for every hook context those IDs correspond to.
As such, don't expect this subroutine to do anything of value if you attempt
to reorder two IDs for the same event and category but one is a post hook and
the other a pre hook, etc.

=cut

sub reorder_hooks {
    my @ids = @_;
    if ( !@ids ) {
        $ERRORMSG = "No IDs passed in to reorder_hooks, nothing to do!";
        return;
    }
    my $new_weight = 1;
    my $seen       = {
        'category' => {},
        'event'    => {},
        'stage'    => {},
    };

    # The below may be confusing. We make a map of what weight these new events
    # should be first. Depending on the order we determine in the map we make
    # here is fine in the event that one ID cannot be found, as we return then
    # instead of reordering with a bogus map.
    # Next we iterate over entries from get_hooks_list's return to set
    # the new weight and delete keys that we shouldn't be passing as part of
    # the hook_ref passed to save_hooksdb().
    # Anyways, we additionally keep track of the category, event and stage
    # described in hook entry data for the IDs in question, as if we encounter
    # more than one of those, then we can't actually reorder this set.
    my %weight_map = map { $_ => $new_weight++ } @ids;
    my $hook_db    = [ get_hooks_list( 'id' => \@ids ) ];
    if ( scalar(@ids) ne scalar(@$hook_db) ) {
        $ERRORMSG = "One of the passed in ID(s) does not exist in the hooks database.";
        return;
    }
    foreach my $hook (@$hook_db) {
        foreach my $thing (qw{category event stage}) {
            $seen->{$thing}{ $hook->{$thing} } = 1;
            delete $hook->{$thing} unless $thing eq 'stage';
        }

        # Give it a new weight gradieted by 100
        $hook->{'weight'} = $weight_map{ $hook->{'id'} } * 100;
    }

    # If there's more than one key to these seen entries, the caller goofed
    if ( grep { scalar( keys(%$_) ) != 1 } ( $seen->{'category'}, $seen->{'event'}, $seen->{'stage'} ) ) {
        $ERRORMSG = "At least one of the provided ids is not in the same category, event and stage as the other provided ids.";
        return;
    }

    # We should have returned already if more than one key exists for these,
    # so only checking first key is fine
    my $category = ( keys( %{ $seen->{'category'} } ) )[0];
    my $event    = ( keys( %{ $seen->{'event'} } ) )[0];

    # XXX May not actually be necessary to sort here, as we consult the weight
    # param when executing the hooks for the given context to determine order,
    # not array order. Probably looks nicer in the YAML & API return though.
    $hook_db = [ sort { int $a->{'weight'} <=> int $b->{'weight'} } @$hook_db ];
    save_hooksdb( $category, $event, $hook_db, 1 );

    return $hook_db;
}

=head2 edit_hook ( $id, %attrs )

For the given hook entry $id, replace the current keys of the event with the
provided %attrs.

Valid attrs to edit are hook, stage, exectype, weight, enabled, notes, check,
escalateprivs and rollback. If none of these are passed in, the subroutine will
die. The subroutine will also die if no $id is passed in.

Returns LIST of category, event, stage and 1 (indicating success).

=cut

sub edit_hook {
    my ( $id, %attrs ) = @_;
    die "edit_hook requires a hook ID passed in." if !$id;

    # Filter out bogus values
    %attrs = map { $_ => $attrs{$_} } grep { exists $attrs{$_} && defined $attrs{$_} } qw{hook stage exectype weight enabled disabled notes check rollback escalateprivs};
    die "edit_hook requires that you edit at least one component of the hook you specified to edit" if !%attrs;

    # Transform "enabled" into "disabled" when passed in
    if ( defined( $attrs{'enabled'} ) ) {
        $attrs{'disabled'} = !delete $attrs{'enabled'} || 0;
    }

    my @hooks = get_hooks_list( 'id' => $id );
    die "Requested hook with ID $id does not exist." if !@hooks;
    die "There can only be one hook with ID $id."    if ( scalar @hooks != 1 );

    my $category = delete $hooks[0]->{'category'};
    my $event    = delete $hooks[0]->{'event'};
    my $stage    = $hooks[0]->{'stage'};

    # Now just allow the passed in attrs to override existing values.
    $hooks[0] = {
        %{ $hooks[0] },
        %attrs,
    };
    my $result = save_hooksdb( $category, $event, \@hooks, 1 );

    return ( $category, $event, $stage, $result );
}

=head2 prune

Deletes all hook entries that no longer correspond to either a script or module
on the filesystem. This was created to resolve issues where a user failed to
run manage_hooks to delete their hooks before deleting their integration's
files. This way we can simply repair any damage that was done and go on our
merry way. Invoked every upcp via scripts/register_hooks.
Returns 1, prints any deleted entries to the default filehandle (probably
STDOUT).

=cut

sub prune {
    my $hooks_db = load_all_hooks();
    foreach my $category ( keys(%$hooks_db) ) {
        next if ref $hooks_db->{$category} ne 'HASH';
        foreach my $event ( keys( %{ $hooks_db->{$category} } ) ) {
            next if ref $hooks_db->{$category}{$event} ne 'ARRAY';
            foreach my $hook ( @{ $hooks_db->{$category}{$event} } ) {
                my $exists = $hook->{'exectype'} eq 'script' ? _script_exists( $hook->{'hook'} ) : _sub_exists( $hook->{'hook'} );
                if ( !$exists ) {
                    $hook->{'category'} = $category;
                    $hook->{'event'}    = $event;
                    my $res = Cpanel::Hooks::Manage::delete(%$hook);
                    if ($res) {
                        print "Deleted hook " . $hook->{'hook'} . " for " . $category . "\:\:" . $event . " in hooks registry, as the referenced hook action code/script no longer exists\n";
                    }
                    elsif ($Cpanel::Hooks::Manage::ERRORMSG) {
                        print $Cpanel::Hooks::Manage::ERRORMSG . "\n";
                        $Cpanel::Hooks::Manage::ERRORMSG = '';
                    }
                }
            }
        }
    }
    return 1;
}

sub _script_exists {
    my ($script) = @_;

    # People pass args in these thing, so only get the first part of the string
    ($script) = split( /\s/, $script );

    return -x $script;
}

sub _sub_exists {
    my ($sub) = @_;
    my @parts = split( '::', $sub );
    $sub = pop @parts;
    my $module = join( '::', @parts );

    local $@;
    eval "require $module";    ## no critic qw(ProhibitStringyEval) -- Basically the only good way to do this
    return $module->can($sub);
}

# returns 1 if the hooks match, 0 if they do not.
# $hook should be a hashref of the hook as it exists in the hooks registry
# ref should be what you are comparing it against
# if a hash key does not exist in ref, it should not be used for evaluating the comparison.
sub _cmp_hooks {
    my ( $hook, $ref ) = @_;
    foreach my $key ( keys %{$ref} ) {
        next   if $key eq 'weight';
        next   if $key eq 'description';
        return if !defined $hook->{$key};
        return if $ref->{$key} ne $hook->{$key};
    }
    return 1;
}

=head2 save_hooksdb

Saves the hooks DB for the given $category and $event using the $ref2store
provided as the data to save. Optionally can be passed "incomplete" $ref2store
data if you wish to $merge the entry with existing data in the Hooks DB.

Example:

    # Overwrite the entry
    Cpanel::Hooks::Manage::save_hooksdb( 'SomeCategory', 'SomeEvent', $arrayref );

    # Update the entry with partial data you merge in
    Cpanel::Hooks::Manage::save_hooksdb( 'SomeCategory', 'SomeEvent', $partial_arrayref, 1 );

=cut

sub save_hooksdb {
    my ( $category, $event, $ref2store, $merge ) = @_;
    return                                   if ( !$category && !$event || grep { Cpanel::Hooks::is_name_invalid($_) } ( $category, $event ) );
    die "This operation must be ran as root" if $>;

    # Merge ref2store with existing data first if we want to do that
    if ($merge) {

        # Will be a load from memory if done in context of edit or reorder
        my $cur_entries = Cpanel::Hooks::load_hooks_for( $category, $event );
        while ( my $entry = shift @$ref2store ) {
            if ( my ($cur_ref) = grep { $entry->{'id'} eq $_->{'id'} } @$cur_entries ) {
                %$cur_ref = %$entry;
            }
            else {
                push @$cur_entries, $entry;
            }
        }
        $ref2store = $cur_entries;
    }

    # Ensure hook data dir exists if it doesn't.
    require Cpanel::Mkdir;
    my $dir = "$Cpanel::Hooks::HOOKS_DB_DIR/data/$category";
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, 0755 );
    my $file = "$dir/$event.yaml";

    # We should have died by now if $category and $event are not legit.
    my $cache = substr( $file, 0, -5 ) . ".cache";
    if ( !$ref2store || ref $ref2store ne 'ARRAY' || !scalar(@$ref2store) ) {

        # Delete it instead, as the new entry is empty
        require Cpanel::Autodie::Unlink;
        Cpanel::Autodie::Unlink::unlink_if_exists_batch( $file, $cache );
        Cpanel::CachedDataStore::clear_one_cache($file);
        delete $Cpanel::Hooks::loaded{$category};
        return 1;
    }
    require Cpanel::CachedDataStore;
    $Cpanel::Hooks::loaded{$category}->{$event} = $ref2store;
    Cpanel::CachedDataStore::store_ref( $file, $ref2store );
    return 1;
}

sub _change_legacy_opts {
    my ($OPTS) = @_;

    # case 56443: Legacy support for old terms
    # NOTE: don't squash new terms
    my %legacy_map = (
        'namespace' => 'category',
        'function'  => 'event',
    );
    foreach ( keys(%legacy_map) ) {
        next if !defined( $OPTS->{$_} );
        my $legacy_value = delete $OPTS->{$_};
        $OPTS->{ $legacy_map{$_} } = $legacy_value if !defined $OPTS->{ $legacy_map{$_} };
    }
    return;
}

=head2 load_all_hooks

Returns HASHREF of hook event HASHREFs keyed by category. The hook events
HASHREF contains ARRAYREFs of hook entries keyed by event. Entry ARRAYREFS
contain HASHREFs of hook entry data.

Example:

    {
        'Category1' => {
            'Event1' => [
                {
                    'exectype' => 'script',
                    ...,
                },
            ],
            ...,
        },
        ...,
    }

The first time you run this subroutine in your execution context may be
expensive, as this entails loading all hook files. Further executions within
the same execution context, however, are all cached in memory by
Cpanel::CachedDataStore, so further consultation is usually trivial timewise.

If, for some reason, you feel that you need to forcibly refetch due to changes
on the filesystem, then setting:

    $Cpanel::Hooks::Manage::all_loaded = 0;

will cause the next invocation of load_all_hooks to scan for new hooks, etc.

Additionally supports passing HASH of "filter arguments". Supported args:
'category', 'event', 'id'.

Note that all those args are simply strings other than ID, which is either
a string OR an arrayref of strings (if you wanna match multiple IDs).

=cut

# Only caller outside of here is in bin/manage_hooks atm
# Note that I'm not doing a security check on paths here, but that is due
# to load_hooks_for already doing this for you before loading data.

sub load_all_hooks {
    my %filter_args = @_;

    my @unsupported = grep {
        my $k = $_;
        !grep { $k eq $_ } qw{category event id}
    } keys(%filter_args);
    die "Unsupported filter argument(s) passed to load_all_hooks: " . join( ", ", @unsupported ) if @unsupported;
    my $hooks_list = {};
    if ($all_loaded) {

        # The cache stores a ref to the cache in CachedDataStore, so we don't
        # want to have callers potentially altering that. Clone it as such.
        require Clone;
        return Clone::clone( \%Cpanel::Hooks::loaded );
    }

    my @categories = $filter_args{'category'} ? ( $filter_args{'category'} ) : Cpanel::Hooks::scandir(
        'dir'    => "$Cpanel::Hooks::HOOKS_DB_DIR/data",
        'wanted' => sub {
            my $file = "$Cpanel::Hooks::HOOKS_DB_DIR/data/$_[0]";
            return ( -d $file );
        },
    );
    foreach my $category (@categories) {
        my $dir2search = "$Cpanel::Hooks::HOOKS_DB_DIR/data/$category";
        if ( $filter_args{'event'} ) {
            next if ( ( -s "$dir2search/$filter_args{'event'}.yaml" || 0 ) < $MIN_SIZE_FOR_YAML_TO_HAVE_DATA );
            my $evt_ar;
            local $@;
            eval { $evt_ar = Cpanel::Hooks::load_hooks_for( $category, $filter_args{'event'}, { 'skip_file_check' => 1, 'filter_id' => $filter_args{'id'} } ); };
            next                                                            if !$evt_ar;
            $hooks_list->{$category} = { $filter_args{'event'} => $evt_ar } if scalar @$evt_ar;
        }
        else {
            my @event_yamls = Cpanel::Hooks::scandir(
                'dir'    => $dir2search,
                'wanted' => sub {
                    my ($entry) = @_;

                    # Only care about YAML files that have data here
                    return if ( substr( $entry, -5 ) ne '.yaml' );
                    return if ( ( -s "$dir2search/$entry" || 0 ) < $MIN_SIZE_FOR_YAML_TO_HAVE_DATA );
                    return 1;
                }
            );
            foreach (@event_yamls) {
                my $event = substr( $_, 0, rindex( $_, "." ) );
                my $evt_ar;
                local $@;
                eval { $evt_ar = Cpanel::Hooks::load_hooks_for( $category, $event, { 'skip_file_check' => 1, 'filter_id' => $filter_args{'id'} } ); };
                next if !$evt_ar;
                if ( scalar(@$evt_ar) ) {
                    $hooks_list->{$category} = {} if ( ref $hooks_list->{$category} ne 'HASH' );
                    $hooks_list->{$category}{$event} = $evt_ar;
                }
            }
        }
    }
    $all_loaded = 1 if !%filter_args;
    return $hooks_list;
}

1;
