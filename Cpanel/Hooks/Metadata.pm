package Cpanel::Hooks::Metadata;

# cpanel - Cpanel/Hooks/Metadata.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Locale ();

my $locale;

# Instructions on how this module is used.
# This module is used by Cpanel::Hooks::Manage as a source of metadata about various different insertion
# points.  This allows us to provide a good UI on top of hooks.  There are a few things that should be noted.
# By default this struct assumes that "pre" and "post" stages will exist for a module. These do not need to be
# defined at the event level.  However if there are other stages, they *must* be documented at
# @$hooks_metadata->{$category}->{$event}->{'stage_order'}.  See the PkgAcct::Restore event for an example of
# how this works.

my $init = 0;

my $hooks_metadata;

sub init {
    $locale ||= Cpanel::Locale->get_handle();
    local $locale->{'-t-STDIN'} = $locale->{'-t-STDIN'};
    $locale->set_context_plain();

    $hooks_metadata = {
        'Whostmgr' => {
            'Accounts::Create' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before an account is created.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'post' => {
                    'description' => $locale->maketext('This runs after an account is created.'),
                },
            },
            'Accounts::Modify' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before an account is modified.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'post' => {
                    'description' => $locale->maketext('This runs after an account is modified.'),
                },
            },
            'Accounts::Remove' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before an account is removed.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'post' => {
                    'description' => $locale->maketext('This runs after an account is removed.'),
                },
            },
            'set_shell' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before an account’s shell is changed.'),
                    'attributes'  => {
                        'blocking' => 1,
                    }
                },
                'post' => {
                    'description' => $locale->maketext('This runs after an account’s shell is changed.'),
                }
            },
            'Transfers::Session' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before a transfer session starts.'),
                    'attributes'  => {
                        'blocking' => 1,
                    }
                },
                'post' => {
                    'description' => $locale->maketext('This runs after a transfer session finishes.'),
                }
            },
        },
        'Stats' => {
            'RunAll' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before cpanellogd runs for all users.'),
                },
                'post' => {
                    'description' => $locale->maketext('This runs after cpanellogd runs for all users.'),
                },
            },
            'RunUser' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before an individual user’s statistics are processed.'),
                },
                'post' => {
                    'description' => $locale->maketext('This runs after an individual user’s statistics are processed.'),
                },
            },
        },
        'Passwd' => {
            'ChangePasswd' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before a user’s password is changed.'),
                    'attributes'  => {
                        'blocking'      => 1,
                        'escalateprivs' => 1,
                    },
                },
                'post' => {
                    'description' => $locale->maketext('This runs after a user’s password is changed.'),
                    'attributes'  => {
                        'escalateprivs' => 1,
                    },
                },
            },
        },
        'PkgAcct' => {
            'Create' => {
                'stage_order' => [ 'pre', 'preFinalize', 'postFinalize' ],
                'pre'         => {
                    'description' => $locale->maketext('This runs before the pkgacct script runs.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'preFinalize' => {
                    'description' => $locale->maketext('This runs before pkgacct generates an archive but after the contents of the archive have been staged.'),
                },
                'postFinalize' => {
                    'description' => $locale->maketext('This runs after pkgacct generates an archive.'),
                },
            },
            'Restore' => {
                'stage_order' => [ 'preExtract', 'postExtract', 'post' ],
                'preExtract'  => {
                    'description' => $locale->maketext('This runs before the tarball is extracted.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'postExtract' => {
                    'description' => $locale->maketext('This runs after the tarball is extracted but before any work is done with it.'),
                    'attributes'  => {
                        'blocking' => 1,
                    },
                },
                'post' => {
                    'description' => $locale->maketext('This runs after the account is restored.'),
                },
            },
        },
        'System' => {
            'upcp' => {
                'pre' => {
                    'description' => $locale->maketext('This runs before a [asis,cPanel amp() WHM] update.'),
                },
                'post' => {
                    'description' => $locale->maketext('This runs after a [asis,cPanel amp() WHM] update.'),
                },
            },
        },
        'DiskQuota' => {
            'warn' => {
                'pre' => { 'description' => $locale->maketext('This runs when a user is approaching their disk quota.'), },
            },
            'critical' => {
                'pre' => { 'description' => $locale->maketext('This runs when a user is approaching their disk quota.'), },
            },
            'full' => {
                'pre' => { 'description' => $locale->maketext('This runs when a user has reached their disk quota.'), },
            },
        },
    };
    $init = 1;

    return;
}

my @stage_attributes = qw(escalateprivs blocking);

sub get_stage_attributes {
    if ( $_[0] ne 'Cpanel' ) {
        my $stage_hr = _get_stage_hr(@_);

        if ( !defined $stage_hr ) {
            return {
                'blocking'      => 0,
                'escalateprivs' => 0,
            };
        }

        my $attr_hr = $stage_hr->{'attributes'};

        #Make a copy so that changes down the line don't affect the original.
        $attr_hr = $attr_hr ? {%$attr_hr} : {};

        $attr_hr->{$_} ||= 0 for (@stage_attributes);

        return $attr_hr;
    }

    return {
        'blocking'      => 0,
        'escalateprivs' => 1,
    };
}

sub get_stage_order {
    my $event_hr = _get_event_hr(@_);

    if ( $event_hr && $event_hr->{'stage_order'} && ref $event_hr->{'stage_order'} eq 'ARRAY' ) {
        return @{ $event_hr->{'stage_order'} };
    }

    return ( 'pre', 'post' );
}

sub get_stage_description {
    my ( $category, $event, $stage ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    # There are too many events in the Cpanel category to define in the hash above.
    if ( $category eq 'Cpanel' ) {
        my ( $apiversion, $module, $function ) = split( '::', $event, 3 );
        $apiversion = uc $apiversion;
        if ( $stage eq 'pre' ) {
            return $locale->maketext( 'This runs before the “[_1]” call “[_2]”.', $apiversion, "${module}::$function" );
        }
        elsif ( $stage eq 'post' ) {
            return $locale->maketext( 'This runs after the “[_1]” call “[_2]”.', $apiversion, "${module}::$function" );
        }
    }
    else {
        my $stage_hr = _get_stage_hr( $category, $event, $stage );
        if ( $stage_hr && length $stage_hr->{'description'} ) {
            return $stage_hr->{'description'};
        }
    }

    return q{};
}

# Note about the below two subroutines:
# an undef response is an indication that the stage/event does not exist in the hash.
# This should not be treated as an error, but rather default values should be used instead.
sub _get_event_hr {
    my ( $category, $event ) = @_;
    init() if !$init;
    if ( exists $hooks_metadata->{$category} && exists $hooks_metadata->{$category}{$event} ) {
        return $hooks_metadata->{$category}{$event};
    }

    return;
}

sub _get_stage_hr {
    my ( $category, $event, $stage ) = @_;
    my $event_hr = _get_event_hr( $category, $event );
    if ( $event_hr && exists $event_hr->{$stage} ) {
        return $event_hr->{$stage};
    }

    return;
}

# This should only be used by the unit test.
sub _return_metadata {
    init() if !$init;
    return $hooks_metadata;
}

1;
