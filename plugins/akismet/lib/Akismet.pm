package MT::Akismet;
use strict;

use base qw( MT::ErrorHandler );

use LWP::UserAgent;
use Carp qw( croak );

our $VERSION = '0.02';

sub check       { shift->_akismet('comment-check', 1, @_) }
sub submit_spam { shift->_akismet('submit-spam',   0, @_) }
sub submit_ham  { shift->_akismet('submit-ham',    0, @_) }

sub verify {
    my ($class, $key, $url, $agent) = @_;
    return $class->error("An Akismet API key is a required parameter.")
      unless $key;
    return $class->error("The URL of the site is a required parameter.")
      unless $url;
    $agent ||= $class->_get_agent;
    my $r =
      $agent->post('http://rest.akismet.com/1.1/verify-key',
                   {key => $key, blog => $url});

    # Could be more RESTful in that status code should indicate success
    # or failure not a string in the content of the response.
    my $res = MT::Akismet::Response->new;
    $res->http_response($r);
    $res->http_status($r->code);
    $res->status($r->is_success && $r->content =~ /valid/i ? 1 : 0);
    $res;
}

#--- internals

sub _akismet {
    my ($class, $meth, $is_true, $sig, $key, $agent) = @_;
    return $class->error("An Akismet API key is a required parameter.")
      unless $key;
    $agent ||= $class->_get_agent;
    my $r =
      $agent->post("http://$key.rest.akismet.com/1.1/$meth", [%ENV, %$sig]);
    my $res = MT::Akismet::Response->new;
    $res->http_response($r);
    $res->http_status($r->code);
    my $status = 0;
    if ($r->is_success) {
        $status = $is_true ? $r->content =~ /false/i : 1;
    }
    $res->status($status);    # 1 (true) means valid api key or not spam.
    $res;
}

our $AGENT;

sub _get_agent {
    my $class = shift;
    return $AGENT if $AGENT;
    $AGENT = LWP::UserAgent->new;
    $AGENT->agent(join '/', $class, $class->VERSION);
    $AGENT->timeout(10);
    $AGENT;
}

package MT::Akismet::Signature;
use base qw( Class::Accessor::Fast );
MT::Akismet::Signature->mk_accessors(
    qw( blog user_ip user_agent referrer permalink comment_type
      comment_author comment_author_email comment_author_url
      comment_content )
);

package MT::Akismet::Response;
use base qw( Class::Accessor::Fast );
MT::Akismet::Response->mk_accessors(qw( status http_status http_response ));

1;
