package Whostmgr::Transfers::Systems::MailFix;

# cpanel - Whostmgr/Transfers/Systems/MailFix.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK

#----------------------------------------------------------------------
#NOTE: This is something of a "kitchen-sink" module since there are so
#many calls to external scripts that deal with "fix-ups" of extracted
#mail components.
#----------------------------------------------------------------------

use Cpanel::ServerTasks       ();
use Cpanel::Dovecot::Solr     ();
use Cpanel::LoadFile          ();
use Cpanel::Services::Enabled ();
use Cpanel::AccessIds         ();

use parent qw(
  Whostmgr::Transfers::SystemsBase::Distributable::Mail
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This repairs mail permissions and upgrades the system to the latest storage methods.') ];
}

sub get_restricted_available {
    return 1;
}

sub restricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    $self->_mbx_conversion();

    $self->start_action('Fixing mail permissions');
    $self->out( $self->_safe_run_errors( '/usr/local/cpanel/scripts/mailperm', '--skiplocaldomains', $newuser ) );

    $self->start_action('Converting to maildir if needed');
    $self->out( $self->_safe_run_errors( '/usr/local/cpanel/bin/convertmaildir', $newuser ) );

    $self->_convert_files_to_local_mailserver_type();

    $self->_rescan_fts_if_needed();

    return 1;
}

sub _mbx_conversion {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my $mbx_file = "$extractdir/meta/mbx";

    return 1 if !-e $mbx_file;

    $self->start_action('Converting mbx to mbox');
    open( my $fh, '<', $mbx_file ) or do {
        $self->warn( $self->_locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $mbx_file, $! ) );
        return;
    };

    my $newuser      = $self->{'_utils'}->local_username();
    my $user_homedir = $self->{'_utils'}->homedir();

    local $!;
    my @paths;
    while ( my $file = readline($fh) ) {
        chomp($file);
        push @paths, "$user_homedir/$file";
    }
    if ($!) {
        $self->warn( $self->_locale()->maketext( 'The system failed to read the file “[_1]” because of an error: [_2]', $mbx_file, $! ) );
        return;
    }

    close($fh) or do {
        $self->warn( $self->_locale()->maketext( 'The system failed to close the file “[_1]” because of an error: [_2]', $mbx_file, $! ) );
        return;
    };

    if (@paths) {
        Cpanel::AccessIds::do_as_user(
            $newuser,
            sub {
                # We need to be in a directory where we can write the log.
                chdir($user_homedir);
                foreach my $full_path (@paths) {
                    $self->_safe_run_errors( '/usr/local/cpanel/Whostmgr/Pkgacct/3rdparty/mbx2mbox/mbx2mbox', $full_path );
                }
                return 1;
            }
          )
          or do {
            $self->warn( $self->_locale()->maketext( 'The system failed to execute the mbx2mbox conversion as the user because of an error: [_2]', $! ) );
            return;
          };
    }

    return 1;
}

sub _convert_files_to_local_mailserver_type {
    my ($self) = @_;

    my $newuser         = $self->{'_utils'}->local_username();
    my $extractdir      = $self->extractdir();
    my $mailserver_file = "$extractdir/meta/mailserver";

    if ( -s $mailserver_file ) {
        my $mailserver = Cpanel::LoadFile::loadfile($mailserver_file) or do {
            $self->warn( $self->_locale()->maketext( 'The system failed to read the file “[_1]” because of an error: [_2]', $mailserver_file, $! ) );
        };

        $mailserver ||= q{};
        chomp $mailserver;

        if ( $mailserver eq 'courier' ) {
            $self->out( $self->_safe_run_errors( '/usr/local/cpanel/scripts/maildir_converter', '--forreal', '--to-dovecot', $newuser ) );
        }
    }
    return 1;
}

sub _rescan_fts_if_needed {
    my ($self) = @_;

    return if !_solr_is_installed_and_enabled();

    my $newuser = $self->{'_utils'}->local_username();

    $self->start_action('Rescanning mailboxes for full text search (FTS) if needed');

    require Whostmgr::Email::Action;
    require Cpanel::Dovecot::FTSRescanQueue::Adder;

    eval {
        my $rescanned_count = Whostmgr::Email::Action::do_with_each_mail_account(
            $newuser,
            sub {
                my ($email_account) = @_;
                Cpanel::Dovecot::FTSRescanQueue::Adder->add($email_account);

            }
        );

        print "...$rescanned_count rescanned... Done\n";
    };
    $self->warn($@) if $@;

    eval { Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 10, 'fts_rescan_mailbox' ); };
    $self->warn($@) if $@;

    return 1;
}

sub _solr_is_installed_and_enabled {
    return Cpanel::Dovecot::Solr::is_installed() && Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr');
}

*unrestricted_restore = \&restricted_restore;

1;
