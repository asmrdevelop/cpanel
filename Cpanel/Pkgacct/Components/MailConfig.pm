package Cpanel::Pkgacct::Components::MailConfig;

# cpanel - Cpanel/Pkgacct/Components/MailConfig.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::MailConfig

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('MailConfig');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s mail config (e.g., valiases) information.

=head1 METHODS

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::ConfigFiles      ();
use Cpanel::LoadFile         ();
use Cpanel::FileUtils::Write ();

#----------------------------------------------------------------------

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform ($self) {

    my $domains_ar = $self->get_cpuser_data()->domains_ar();

    my $skipmailman = $self->get_OPTS()->{'skipmailman'};
    my $work_dir    = $self->get_work_dir();

    foreach my $domain (@$domains_ar) {
        if ( -e "$Cpanel::ConfigFiles::VALIASES_DIR/${domain}" ) {

            $self->syncfile_or_warn( "$Cpanel::ConfigFiles::VALIASES_DIR/${domain}", "$work_dir/va/$domain" );
            if ($skipmailman) {
                my $valiases_content = Cpanel::LoadFile::loadfileasarrayref("$work_dir/va/$domain");
                chomp @{$valiases_content};
                Cpanel::FileUtils::Write::overwrite_no_exceptions( "$work_dir/va/$domain", ( join "\n", ( grep { !_is_mailman_valias($_) } @{$valiases_content} ) ) . "\n", 0640 );
            }
        }
        if ( -e "$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/${domain}" ) {
            $self->syncfile_or_warn( "$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/${domain}", "$work_dir/vad/$domain" );
        }
        if ( -e "$Cpanel::ConfigFiles::VFILTERS_DIR/${domain}" ) {
            $self->syncfile_or_warn( "$Cpanel::ConfigFiles::VFILTERS_DIR/${domain}", "$work_dir/vf/$domain" );
        }
    }

    return 1;
}

sub _is_mailman_valias ($valias_entry) {

    # If the entry is piped to mailman, or if the entry
    # matches the owner-$x@domain.com: $x-admin@domain.com pattern,
    # then it is a mailman valias entry:

    return 1 if -1 != index( $valias_entry, '/usr/local/cpanel/3rdparty/mailman/mail/mailman' );

    return 1 if $valias_entry =~ m{^owner-(\w+)\@(.+): \1-(admin|owner)\@\2};

    return;
}

1;
