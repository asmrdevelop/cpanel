package Cpanel::MailAuth::Dovecot;

# cpanel - Cpanel/MailAuth/Dovecot.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::MailAuth::Dovecot

=head1 SYNOPSIS

    my $can_proxy = Cpanel::MailAuth::Dovecot::service_can_proxy('smtp');

=head1 DESCRIPTION

This module contains bits of logic for cpsrvd’s Dovecot authentication
service.

=cut

#----------------------------------------------------------------------

use Cpanel::Dovecot::Constants      ();
use Cpanel::Quota::Cache::Constants ();

#For SMTP 552 (extended 5.2.2) status
#NOTE: Accessed from tests
our $_OVER_QUOTA_TXT = 'Mailbox is full / Blocks limit exceeded / Inode limit exceeded';

my %DOVECOT_SERVICES_NOT_TO_PROXY = (

    # “smtp” == Exim. Since Exim doesn’t understand Dovecot’s proxying,
    # we need to send a password and force it to authenticate. Otherwise,
    # Exim forgoes SMTP authentication!
    #
    # In the case of live transfers this is unideal since the destination
    # server might have an updated password--which would mean our
    # authentication will require the old password, which could confuse the
    # user--but that’s at least better than forgoing SMTP authentication
    # entirely.
    smtp => undef,

    # As of Dovecot 2.3.11, if we send the proxying stuff (e.g., ssl=any-cert)
    # in a userdb response to doveadm, then doveadm complains about not
    # recognizing the response. We don’t want to proxy doveadm requests
    # anyway, so let’s just skip the proxying in those cases.
    doveadm => undef,
);

our $BLOCK_TO_BYTES = 1024;

# We need to avoid an overflow with `doveadm quota get -u overflowquota` when the quota is set
# larger than int64 which results in
#
# Invalid quota root quota2: Invalid rule *:bytes=9999999999999999k: Bytes limit can't be negative
#
# We currenly have a 4PB limit for quota which is enforced in the UI
# In the future we could raise this as high as ~0 >> 1
#
# Dovecot will support as high as str_parse_int64
# in https://github.com/dovecot/core/blob/master/src/plugins/quota/quota-util.c
#
my $MAX_INT         = 2147483647;
my $MAX_LIMIT_VALUE = 4 * 1024**5;
my $MAX_BYTES_LIMIT = $MAX_LIMIT_VALUE;
my $MAX_BLOCK_LIMIT = $MAX_LIMIT_VALUE / $BLOCK_TO_BYTES;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = service_can_proxy( $SERVICENAME )

Returns a boolean that indicates whether $SERVICENAME is one that Dovecot
will proxy. $SERVICENAME is Dovecot’s C<%s> variable (cf.
L<https://doc.dovecot.org/configuration_manual/config_file/config_variables/#config-variables>).

=cut

sub service_can_proxy ($servicename) {
    return !exists $DOVECOT_SERVICES_NOT_TO_PROXY{$servicename};
}

# This converts the results from Cpanel::AcctUtils::Lookup::MailUser
# into something Cpanel::MailAuth can consume
sub convert_lookup_mail_user_to_mailauth {
    my ( $mail_user_info, $used_domainowner_auth ) = @_;
    return {
        'USERNAME'    => $mail_user_info->{'passwd'}->{'user'},
        'ADDRESS'     => $mail_user_info->{'passwd'}->{'address'},
        'UID'         => $mail_user_info->{'passwd'}->{'uid'},
        'GID'         => $mail_user_info->{'passwd'}->{'gid'},
        'HOME'        => $mail_user_info->{'passwd'}->{'homedir'},
        'MAILDIR'     => $mail_user_info->{'passwd'}->{'maildir'},
        'UTF8MAILBOX' => $mail_user_info->{'mailbox'}->{'utf8'},
        'FORMAT'      => $mail_user_info->{'mailbox'}->{'format'},
        'PASSWD'      => $mail_user_info->{'shadow'}->{ ( $used_domainowner_auth ? 'domainowner' : 'user' ) },
        'AUTOCREATE'  => $mail_user_info->{'mailbox'}->{'autocreate'} // 1,
        ( $mail_user_info->{'quota'}->{'value'}            ? ( 'QUOTA'            => $mail_user_info->{'quota'}->{'value'} . 'S' )      : () ),
        ( $mail_user_info->{'mailbox'}->{'namespace'}      ? ( 'NAMESPACE'        => $mail_user_info->{'mailbox'}->{'namespace'} )      : () ),
        ( $mail_user_info->{'quota'}->{'disk_block_limit'} ? ( 'DISK_BLOCK_LIMIT' => $mail_user_info->{'quota'}->{'disk_block_limit'} ) : () ),
        ( $mail_user_info->{'quota'}->{'disk_inode_limit'} ? ( 'DISK_INODE_LIMIT' => $mail_user_info->{'quota'}->{'disk_inode_limit'} ) : () ),
        'ACCOUNT_TYPE'  => $mail_user_info->{'account_type'},
        'PROXY_BACKEND' => $mail_user_info->{'proxy_backend'},
    };
}

# This converts the output to something dovecot
# can consume
sub augment_hashref_with_auth_result ( $hashref, $auth_result, $service, $prefix ) {

    # This all has to be here even when proxying so that dsync still works.

    if ( my $custom_ns = $auth_result->{'NAMESPACE'} ) {
        $hashref->{ $prefix . 'namespace/inbox/inbox' }      = 'no';
        $hashref->{ $prefix . "namespace/$custom_ns/inbox" } = 'yes';
    }

    $hashref->{ $prefix . 'uid' }  = $auth_result->{'UID'};
    $hashref->{ $prefix . 'gid' }  = $auth_result->{'GID'};
    $hashref->{ $prefix . 'home' } = $auth_result->{'HOME'};
    $hashref->{ $prefix . 'mail' } = "$auth_result->{'FORMAT'}:$auth_result->{'MAILDIR'}";
    $hashref->{ $prefix . 'mail' } .= ":UTF-8" if $auth_result->{'UTF8MAILBOX'};

    # Everything below suits specific use cases.

    my $needs_password = 1;

    if ( my $backend = $auth_result->{'PROXY_BACKEND'} ) {

        # Dovecot only proxies certain services. For those services
        # we omit the password from the userdb response, which tells
        # Dovecot to forgo authentication.
        #
        # For non-proxied services, though, we *DO* need to send the
        # password. With such services we might as well also omit the
        # proxying stuff from the userdb response since it’s just extra
        # cruft that the service will either (at best) discard or
        # (at worst, cf. CPANEL-35441) consider invalid.
        #
        if ( !$service || service_can_proxy($service) ) {
            $needs_password = 0;

            $hashref->{ $prefix . 'proxy_maybe' } = 'y';
            $hashref->{ $prefix . 'host' }        = $backend;
            $hashref->{ $prefix . 'ssl' }         = 'any-cert';
        }
    }
    else {

        # The below is not needed unless whoever is authenticating intends
        # to alter the mailbox.

        if ( !$auth_result->{'AUTOCREATE'} ) {
            $hashref->{ $prefix . 'lda_mailbox_autocreate' } = 'no';
        }

        my $quota_value = $auth_result->{'QUOTA'} ? $auth_result->{'QUOTA'} =~ s{S}{}r : 0;

        if ( $quota_value && $quota_value <= $MAX_BYTES_LIMIT ) {
            $hashref->{ $prefix . 'quota_rule' } = '*:bytes=' . $quota_value;
        }
        else {
            # We must set a quota rule or dovecot quota
            # clone will track the filesystem quota
            # so we set it the maximum allowed number of messages
            # Can probably be MAX_LIMIT_VALUE, but that seem like a risky change at this point;
            $hashref->{ $prefix . 'quota_rule' } = '*:messages=' . $MAX_INT;
        }
        if ( $auth_result->{'FORMAT'} eq 'mdbox' ) {
            $hashref->{ $prefix . 'quota' } = 'count:Mailbox';
        }
        else {
            $hashref->{ $prefix . 'quota' } = 'maildir:Mailbox:ns=INBOX.';
        }

        # Used for tracking so we do not have to read the maildirsize files
        $hashref->{ $prefix . 'quota_clone_dict' } = "file:$auth_result->{'MAILDIR'}/dovecot-quota";
        $hashref->{ $prefix . 'quota_rule2' }      = 'INBOX.INBOX:ignore';

        # We stat the file manually instead of using Cpanel::Dovecot::IncludeTrashInQuota->is_on()
        # because Cpanel::Dovecot::IncludeTrashInQuota requires to much memory at this time
        if ( !-e $Cpanel::Dovecot::Constants::INCLUDE_TRASH_IN_QUOTA_CONFIG_CACHE_FILE ) {
            $hashref->{ $prefix . 'quota_rule3' } = 'INBOX.Trash:ignore';
        }

        if ( $auth_result->{'ACCOUNT_TYPE'} eq 'system' ) {
            $hashref->{ $prefix . 'quota_rule4' } = 'INBOX.*@*:ignore';
        }

        # We stat the files manually instead of using Cpanel::Quota::Cache::QuotasDisabled->is_on()
        # because Cpanel::Quota::Cache::QuotasDisabled requires to much memory at this time

        if ( !-e $Cpanel::Quota::Cache::Constants::QUOTAS_BROKEN_FLAG_FILE && !-e $Cpanel::Quota::Cache::Constants::QUOTAS_DISABLED_FLAG_FILE ) {

            # Dovecot is in charge of enforcing the quota rules.
            #
            # Each dovecot rule must be postfixed with a number if there
            # are more then on rule.
            #
            # See https://wiki2.dovecot.org/Quota
            #
            $hashref->{ $prefix . 'quota2' }       = 'fs:cPanel Account';
            $hashref->{ $prefix . 'quota2_grace' } = '0';

            # Dovecot has no way to write a quota rule
            # that will use the quota:fs limit since only
            # the maildir++ quota type supports backend
            if ( $auth_result->{'DISK_BLOCK_LIMIT'} && $auth_result->{'DISK_BLOCK_LIMIT'} <= $MAX_BLOCK_LIMIT ) {

                # bytes support b/k/M/G/T/% suffixes
                $hashref->{ $prefix . 'quota2_rule' } = '*:bytes=' . $auth_result->{'DISK_BLOCK_LIMIT'} . 'k';
            }
            if ( $auth_result->{'DISK_INODE_LIMIT'} ) {
                my $rule_name = $auth_result->{'DISK_BLOCK_LIMIT'} ? 'quota2_rule2' : 'quota2_rule';
                $hashref->{ $prefix . $rule_name } = '*:messages=' . $auth_result->{'DISK_INODE_LIMIT'};
            }

        }
        $hashref->{ $prefix . 'quota_vsizes' } = 'yes';

        #
        # case CPANEL-7894
        # Make the error message when they are overquota more helpful
        # in the hopes that its easier to discover they hit an inode
        # limit.
        #
        $hashref->{ $prefix . 'quota_status_overquota' } = "552 5.2.2 $_OVER_QUOTA_TXT";
    }

    if ($needs_password) {

        #
        # lookup_mail_user will NEVER give us a plain text password
        # Cpanel::Server::Dovecot will override the password field
        # for service auth and temp users
        #
        $hashref->{ $prefix . 'password' } = '{CRYPT}' . $auth_result->{'PASSWD'};
    }
    else {
        $hashref->{ $prefix . 'nopassword' } = 'y';
    }

    return 1;
}

# Must be the original user before it gets transformed
# from _mainaccount@xxxx.org or _archive@ko.org to -> user
sub get_alternate_namespace_or_die {
    my ( $original_user, $userdata_after_slash ) = @_;
    if ($userdata_after_slash) {
        if ( $original_user =~ tr{_}{} && $original_user =~ m/^_archive[+%:@]/ ) {
            die "Archive users cannot have a namespace.";
        }
        elsif ( $userdata_after_slash eq 'sent' ) {
            return 'sent';
        }
        elsif ( $userdata_after_slash eq 'spam' ) {
            return 'spam';
        }
        else {
            die "Unknown namespace “$userdata_after_slash”";
        }

    }
    return undef;
}

1;
