package Cpanel::Email::Mailbox::Format;

# cpanel - Cpanel/Email/Mailbox/Format.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule             ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Email::Mdbox::Utils    ();
use Cpanel::Email::Maildir::Utils  ();

sub get_mailbox_format_for_user {
    my ($user) = @_;
    return Cpanel::Config::LoadCpUserFile::load_or_die($user)->{'MAILBOX_FORMAT'} || get_mailbox_format_for_new_accounts();
}

sub get_mailbox_format_for_new_accounts {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    return $cpconf->{'mailbox_storage_format'} if $cpconf->{'mailbox_storage_format'};

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard::Default');
    return Cpanel::Config::CpConfGuard::Default::default_statics()->{'mailbox_storage_format'};
}

sub get_relative_dirs_to_create {
    my ($mailbox_format) = @_;

    if ( !length $mailbox_format ) {
        die "get_relative_dirs_to_create requires the mailbox_format";
    }

    if ( $mailbox_format eq 'mdbox' ) {
        return Cpanel::Email::Mdbox::Utils::get_relative_dirs_to_create();
    }
    return Cpanel::Email::Maildir::Utils::get_relative_dirs_to_create();
}

sub get_mailbox_format_file_path {
    my ($user_homedir) = @_;

    return "$user_homedir/mail/mailbox_format.cpanel";
}

1;
