-module(kbucket).
-export([start/2]).
-export([loop/1]).
-export([put/2]).
-export([closest_contacts/2]).

-define (TIMEOUT_PONG, 100).

-type contact() :: {pid(), integer()} .

-record(kbucket, {id, k, contacts}).

start(OwningPeerId, K) ->
    Kbucket = #kbucket{id=OwningPeerId, k=K, contacts=#{}},
    spawn(fun() -> loop(Kbucket) end).

put(KbucketPid, PeerId) ->
    KbucketPid ! {put, PeerId},
    ok.

get(KbucketPid, Distance) ->
    KbucketPid ! {get, self(), Distance},
    receive
        {KbucketPid, Bucket} -> Bucket
    end.

closest_contacts(KbucketPid, Key) ->
    KbucketPid ! {closest_contacts, self(), Key},
    receive
        {KbucketPid, Contacts} -> Contacts
    end.

loop(Kbucket) ->
    receive
        {put, Contact} ->
            NewKbucket = handle_put(Contact, Kbucket),
            loop(NewKbucket);

        {closest_contacts, FromPeer, Key} ->
            ClosestContacts = handle_closest_contacts(Key, Kbucket),
            FromPeer ! {self(), ClosestContacts},
            loop(Kbucket);

        {get, FromPeer, BucketIndex} ->
            FromPeer ! {self(), bucket(BucketIndex, Kbucket)},
            loop(Kbucket);

        _ ->
            loop(Kbucket)
    end.

handle_closest_contacts(Key, Kbucket) ->
    AllContacts = all_contacts(Kbucket),
    SortedContacts = lists:sort(fun({_, FirstId}, {_, SecondId}) ->
                                    distance(Key, FirstId) =< distance(Key, SecondId)
                                end, AllContacts),
    lists:sublist(SortedContacts, Kbucket#kbucket.k).

all_contacts(Kbucket) ->
    Contacts = Kbucket#kbucket.contacts,
    Indexes = maps:keys(Contacts),
    AllContacts = lists:map(fun(Index) ->
                                #{Index := BucketContacts} = Contacts,
                                BucketContacts
                            end, Indexes),
    lists:flatten(AllContacts).

handle_put({_, PeerId} = Contact, Kbucket) ->
    BucketIndex = bucket_index(distance(Kbucket#kbucket.id, PeerId)),
    Bucket = bucket(BucketIndex, Kbucket),
    Contacts = Kbucket#kbucket.contacts,
    NewContacts = Contacts#{BucketIndex => put_on(Bucket, Contact, Kbucket)},
    Kbucket#kbucket{contacts=NewContacts}.

put_on([LeastContact | PartialBucket] = Bucket, Contact, Kbucket)
  when length(Bucket) =:= Kbucket#kbucket.k ->
    {PeerPid, _} = LeastContact,
    peer:ping(PeerPid),
    receive
        {pong, PeerPid} ->
            Bucket
    after ?TIMEOUT_PONG ->
        put_on(PartialBucket, Contact, Kbucket)
    end;
put_on(Bucket, Contact, _) ->
    CleanedBucket = lists:delete(Contact, Bucket),
    lists:append(CleanedBucket, [Contact]).

bucket(BucketIndex, Kbucket) ->
    Contacts = Kbucket#kbucket.contacts,
    case maps:is_key(BucketIndex, Contacts) of
        true -> #{BucketIndex := Bucket} = Contacts,
                Bucket;
        _    -> []
    end.

distance(FromPeerId, ToPeerId) ->
    FromPeerId bxor ToPeerId.

bucket_index(Distance) ->
    trunc(math:log2(Distance)).

-ifdef(TEST).
-compile([export_all]).
-include_lib("../test/kbucket.hrl").
-endif.
