CTrackManiaPlayerInfo@ NetPIToTrackmaniaPI(CGameNetPlayerInfo@ netpi) {
  return cast<CTrackManiaPlayerInfo@>(netpi);
}

MwFastBuffer<CMapRecord@> playerScores = MwFastBuffer<CMapRecord@>();
array<LeaderboardPlayer@> leaderboardPlayers; 
array<string> listedUserIdsStrArray;

class LeaderboardPlayer {
  int Rank;
  int Time;
  Player@ Player;

  LeaderboardPlayer(int rank, int time, Player@ player) {
    Rank = rank;
    Time = time;
    @Player = player;
  }

  string getTime(){
    return this.Time > 0 ? Time::Format(this.Time) : "-:--.---";
  }

  int opCmp(const LeaderboardPlayer &in leaderboardPlayer) const {
    if(this.Time == 0){
      return 0;
    }

    return this.Time < leaderboardPlayer.Time ? -1 : 0;
  }
}

class Player {
  string AccountID;
  string DisplayName;

  Player(const string &in accountID, const string &in displayName) {
    AccountID = accountID;
    DisplayName = displayName;
  }
}

string searchText = "";
bool startSearch = false;
array<Player@> tmioSearchResult;


string SendJSONRequest(const Net::HttpMethod Method, const string &in URL, string Body = "") {
  dictionary@ Headers = dictionary();
  Headers["Accept"] = "application/json";
  Headers["Content-Type"] = "application/json";
  return SendHTTPRequest(Method, URL, Body, Headers);
}

Json::Value ResponseToJSON(const string &in HTTPResponse, Json::Type ExpectedType) {
  Json::Value ReturnedObject;
  try {
    ReturnedObject = Json::Parse(HTTPResponse);
  } catch {
  }
  if (ReturnedObject.GetType() != ExpectedType) {
    return ReturnedObject;
  }
  return ReturnedObject;
}


string SendHTTPRequest(const Net::HttpMethod Method, const string &in URL, const string &in Body, dictionary@ Headers) {
  Net::HttpRequest req;
  req.Method = Method;
  req.Url = URL;
  @req.Headers = Headers;
  req.Body = Body;

  req.Start();
  while (!req.Finished()) {
    yield();
  }
  return req.String();
}

void SearchTMIOForPlayers() {
  string searchResultResponse = SendJSONRequest(Net::HttpMethod::Get, "https://trackmania.io/api/players/find?search=" + searchText);
  Json::Value searchResult = ResponseToJSON(searchResultResponse, Json::Type::Array);

  if (searchResult.GetType() != Json::Type::Null) {
    try {
      for (uint i = 0; i < searchResult.Length; i++) {
        try {
          tmioSearchResult.InsertLast(Player(searchResult[i]["player"]["id"], searchResult[i]["player"]["name"]));
        } catch {
        }
      }
    } catch {
     
    }
  }
}

void Render() {
  int windowFlags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoDocking;
  if (!UI::IsOverlayShown()) {
      windowFlags |= UI::WindowFlags::NoInputs;
  }

  if(UI::IsOverlayShown()){
    UI::Begin("Add players to your list");
    startSearch = startSearch || false;
    searchText = UI::InputText("Search", searchText, startSearch, UI::InputTextFlags::EnterReturnsTrue);

    UI::BeginGroup();
    if(startSearch){
      print(searchText);
      tmioSearchResult = {};
      startnew(SearchTMIOForPlayers);
    }

    if(UI::BeginTable("header", 2, UI::TableFlags::SizingFixedFit)){
      bool shouldRefreshList = false;

      for(uint i = 0; i < tmioSearchResult.Length; i++){
        UI::TableNextRow();
        UI::TableNextColumn();

        auto playerIndex = listedUserIdsStrArray.Find(tmioSearchResult[i].AccountID);
        if(playerIndex < 0){
          
          UI::PushID("TMIOSearchResult_" + tostring(i));
          if(UI::Button("+", vec2(22.0, 22.0))){
            shouldRefreshList = true;
            print(tmioSearchResult[i].AccountID);
            listedUserIdsStrArray.InsertLast(tmioSearchResult[i].AccountID);
          }
          UI::PopID();
        } else {
			    UI::PushStyleColor(UI::Col::Button, vec4(1.0, 0.0, 0.0, 1.0));
          UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.85, 0.0, 0.0, 1.0));
          UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.9, 0.0, 0.0, 1.0));
          
          UI::PushID("TMIOSearchResult_" + tostring(i));
          if(UI::Button("-", vec2(22.0, 22.0))){
            shouldRefreshList = true;
            listedUserIdsStrArray.RemoveAt(playerIndex);
          }
          
          UI::PopID();
          UI::PopStyleColor(3);
        }

        UI::TableNextColumn();
        UI::Text(tmioSearchResult[i].DisplayName);
      }

      if(shouldRefreshList){
        startnew(RefreshScores);
      }

      UI::EndTable();
    }
    
    UI::EndGroup();
    UI::End();
  }

  UI::Begin("Listed Records", windowFlags);
  UI::BeginGroup();

  if(UI::BeginTable("header", 2, UI::TableFlags::SizingFixedFit)){
    UI::TableNextRow();
    UI::TableNextColumn();
    UI::Markdown("#### Listed Records");

    for(uint i = 0; i < leaderboardPlayers.Length; i++){
      UI::TableNextRow();
      UI::TableNextColumn();
      UI::Text(leaderboardPlayers[i].Player.DisplayName);
      UI::TableNextColumn();
      UI::Text(leaderboardPlayers[i].getTime());
    }
    
    UI::EndTable();
  }

  UI::EndGroup();
  UI::End();
}

void RefreshScores(){
  MwFastBuffer<wstring> listedUserIds = MwFastBuffer<wstring>();
  array<string> tempUserAccountIds;

  auto app = cast<CTrackMania>(GetApp());
  auto map = app.RootMap;
  auto network = cast<CTrackManiaNetwork>(app.Network);
  auto scoreMgr = network.ClientManiaAppPlayground.ScoreMgr;
  auto userMgr = network.ClientManiaAppPlayground.UserMgr;
  auto userId = userMgr.Users[0].Id;

  if(listedUserIdsStrArray.Find(network.PlayerInfo.WebServicesUserId) < 0){
    listedUserIdsStrArray.InsertLast(network.PlayerInfo.WebServicesUserId);
  }

  for(uint i = 0; i < listedUserIdsStrArray.Length; i++){
    listedUserIds.Add(listedUserIdsStrArray[i]);
    tempUserAccountIds.InsertLast(listedUserIdsStrArray[i]);
  }

  auto playerScoreMap = scoreMgr.Map_GetPlayerListRecordList(userId, listedUserIds, map.MapInfo.MapUid, "PersonalBest", "", "", "");
  auto playerNamesMap = userMgr.GetDisplayName(userId, listedUserIds);

  while(!playerScoreMap.HasSucceeded || !playerNamesMap.HasSucceeded){
    sleep(1000);
  }

  // Reset listed player list
  leaderboardPlayers = {};

  if(playerScoreMap.HasSucceeded && playerNamesMap.HasSucceeded){
    playerScores = playerScoreMap.MapRecordList;

    for (uint i = 0; i < playerScores.Length; i++) {
      auto playerScoreInfo = playerScores[i];
      auto time = playerScoreInfo.Time > 0 ? Time::Format(playerScoreInfo.Time) : "-:--.---";
      auto name = playerNamesMap.GetDisplayName(playerScoreInfo.WebServicesUserId);
      auto player = Player(playerScoreInfo.WebServicesUserId, name);
      auto leaderboardPlayer = LeaderboardPlayer(0, playerScoreInfo.Time, player);

      tempUserAccountIds.RemoveAt(tempUserAccountIds.Find(playerScoreInfo.WebServicesUserId));

      leaderboardPlayers.InsertLast(leaderboardPlayer);
    }

    for(uint i = 0; i < tempUserAccountIds.Length; i++){
      auto name = playerNamesMap.GetDisplayName(tempUserAccountIds[i]);
      auto player = Player(tempUserAccountIds[i], name);
      auto leaderboardPlayer = LeaderboardPlayer(0, 0, player);

      leaderboardPlayers.InsertLast(leaderboardPlayer);
    }

    leaderboardPlayers.SortAsc();
  }
}

void Main() {
  // \\$0ff

  listedUserIdsStrArray.InsertLast("79976f5d-179d-4578-baed-7dfd253bca35");
  listedUserIdsStrArray.InsertLast("17cebbbb-2637-4110-ba67-f733de4559ea");
  listedUserIdsStrArray.InsertLast("b02c5f84-0a0c-4931-b5ba-1d68bf9c3b91");
  listedUserIdsStrArray.InsertLast("6a7a889f-cbff-4910-b369-a4201de53cb8");
  RefreshScores();
}