package Whostmgr::Accounts::DB::Remove;

# cpanel - Whostmgr/Accounts/DB/Remove.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Signal::Defer          ();
use Cpanel::Finally                ();
use Cpanel::PwCache                ();
use Cpanel::InternalDBS            ();
use Cpanel::Debug                  ();
use Cpanel::Transaction::File::Raw ();

my %gid_cache;

our $DB_PATH = '/etc';    # for mocking

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::DB::Remove - Tools to remove user and domain data from system internal dbs.

=head1 SYNOPSIS

    use Whostmgr::Accounts::DB::Remove ();

    Whostmgr::Accounts::DB::Remove::remove_user_and_domains($user);

    Whostmgr::Accounts::DB::Remove::remove_user_and_domains($user, ['domain1.tld','domain2.tld']);

=cut

=head2 remove_user_and_domains($user, $domains_ar);

Remove domains and, optionally, a user from the system databases.

The function requires at least one domain, however
the user can be undef since this function is also used
to remove domains from the pseudo “nobody” user.

=over 2

=item Input

=over 3

=item $user C<SCALAR> (optional)

    Remove this user from all of cPanel's
    Cpanel::InternalDBS::get_all_dbs()s

    Passing undef is acceptable.

=item $domains_ref C<ARRAYREF>

    Remove this domain from all of cPanel's
    Cpanel::InternalDBS::get_all_dbs()s

=back

=back

=cut

sub remove_user_and_domains {
    my ( $user, $domain_ref ) = @_;

    if ( !ref $domain_ref || !@$domain_ref ) {
        die('remove_user_and_domains requires at least one domain');
    }

    my %ALL_DOMAINS_TO_REMOVE = map { $_ => undef } @$domain_ref;
    delete @ALL_DOMAINS_TO_REMOVE{ '', ' ', "\n" };    #safety

    my $all_dbs_ref = Cpanel::InternalDBS::get_all_dbs();

    my ( $user_colon_line_end, $user_colon_line_start, $user_equal_line_start, $user_equal_line_start_length, $user_colon_line_start_length, $user_colon_line_end_length ) = _generate_user_matchers($user);
    my $modified = 0;
    my @close;

    # Sort here as well so that we don't deadlock with updateuserdomains
    foreach my $dbref ( sort { $a->{'file'} cmp $b->{'file'} } (@$all_dbs_ref) ) {
        my ( $format, $file, $group, $permissions ) = @{$dbref}{qw(format file group perms)};
        next                             if !$format;        # If there is no format it cannot be trimemd
        die "$file is missing the group" if !$group;
        die "$file is missing perms"     if !$permissions;
        my $gid = _get_cached_user_gid($group);

        my $path = "$DB_PATH/$file";
        next if !-s $path;

        my $trans = Cpanel::Transaction::File::Raw->new( 'path' => $path, ownership => [ 0, $gid ], permissions => $permissions );

        my $data_sr  = $trans->get_data();
        my @matchers = index( $format, 'user' ) > -1 ? ( $user ? $user : () ) : keys %ALL_DOMAINS_TO_REMOVE;
        if ( _sr_contains_value( $data_sr, \@matchers ) ) {
            my @LFILE       = split( m{\n}, $$data_sr );
            my $rows_before = scalar @LFILE;

            if ( $format eq 'domains' ) {
                @LFILE = grep { !exists $ALL_DOMAINS_TO_REMOVE{$_} } @LFILE;
            }
            elsif ( $format eq 'startdomain' ) {
                @LFILE = grep { !exists $ALL_DOMAINS_TO_REMOVE{ substr( $_, 0, index( $_, ':' ) ) } } @LFILE;
            }
            elsif ( $format eq 'enduser' ) {
                @LFILE = grep { $user_colon_line_end ne substr( $_, -1 * $user_colon_line_end_length ) } @LFILE if length $user;
            }
            elsif ( $format eq 'user' ) {
                @LFILE = grep { $_ ne $user } @LFILE if length $user;
            }
            elsif ( $format eq 'eitheruser' ) {
                @LFILE =
                  grep { $user_colon_line_start ne substr( $_, 0, $user_colon_line_start_length ) && $user_colon_line_end ne substr( $_, -1 * $user_colon_line_end_length ) } @LFILE
                  if length $user;

            }
            elsif ( $format eq 'startuser' ) {
                @LFILE = grep { $user_colon_line_start ne substr( $_, 0, $user_colon_line_start_length ) } @LFILE if length $user;

            }
            elsif ( $format eq 'startuserequal' ) {
                @LFILE = grep { $user_equal_line_start ne substr( $_, 0, $user_equal_line_start_length ) } @LFILE if length $user;
            }
            else {
                die "Internal Error: $format type does not exist";
            }

            if ( $rows_before != scalar @LFILE ) {

                # we have changes
                $trans->set_data( \join( "\n", @LFILE, '' ) );
                push @close, [ $trans, 1, $path ];
                $modified = 1;

            }
        }

        if ( !$modified ) {
            push @close, [ $trans, 0, $path ];
        }

    }
    my ( $defer, $undefer );
    if ($modified) {
        ( $defer, $undefer ) = _defer_signals();
    }
    _close_transactions( \@close );
    if ($defer) {
        $defer->restore_original_signal_handlers();
        $undefer->skip();
    }
    return;
}

sub _close_transactions {
    my ($close_ref) = @_;
    foreach my $trans_ref (@$close_ref) {
        my ( $trans, $save_and_close, $path ) = @$trans_ref;
        if ($save_and_close) {
            my ( $save_ok, $save_msg ) = $trans->save_and_close( 'signals_already_deferred' => 1 );
            if ( !$save_ok ) {
                Cpanel::Debug::log_warn("The system failed to save changes to “$path” because of an error: $save_msg");
            }
        }
        else {
            my ( $close_ok, $close_msg ) = $trans->close();
            if ( !$close_ok ) {
                Cpanel::Debug::log_warn("The system failed to close “$path” because of an error: $close_msg");
            }

        }
    }
    return;
}

sub _get_cached_user_gid {
    my ($user) = @_;
    return ( $gid_cache{$user} ||= ( Cpanel::PwCache::getpwnam_noshadow($user) )[3] );
}

sub _defer_signals {
    my $defer = Cpanel::Signal::Defer->new(
        defer => {
            signals => Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS(),
            context => "writing remove_user_and_domains to disk",
        }
    );
    my $undefer = Cpanel::Finally->new(
        sub {
            $defer->restore_original_signal_handlers();
            undef $defer;
        }
    );

    return ( $defer, $undefer );

}

sub _generate_user_matchers {
    my ($user) = @_;
    if ( length $user ) {
        my $user_colon_line_end          = ": $user";
        my $user_colon_line_start        = "$user:";
        my $user_equal_line_start        = "$user=";
        my $user_equal_line_start_length = length $user_equal_line_start;
        my $user_colon_line_start_length = length $user_colon_line_start;
        my $user_colon_line_end_length   = length $user_colon_line_end;
        return ( $user_colon_line_end, $user_colon_line_start, $user_equal_line_start, $user_equal_line_start_length, $user_colon_line_start_length, $user_colon_line_end_length );
    }
    return ();
}

sub _sr_contains_value {
    my ( $data_sr, $matchers_ar ) = @_;
    foreach my $key (@$matchers_ar) {
        if ( index( $$data_sr, $key ) > -1 ) {
            return 1;
        }
    }
    return 0;
}

1;
