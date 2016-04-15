// Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
// See License.txt for license information.

package api

import (
	"github.com/dotcominternet/platform/model"
)

type MeProvider struct {
}

const (
	CMD_ME = "me"
)

func init() {
	RegisterCommandProvider(&MeProvider{})
}

func (me *MeProvider) GetTrigger() string {
	return CMD_ME
}

func (me *MeProvider) GetCommand(c *Context) *model.Command {
	return &model.Command{
		Trigger:          CMD_ME,
		AutoComplete:     true,
		AutoCompleteDesc: c.T("api.command_me.desc"),
		AutoCompleteHint: c.T("api.command_me.hint"),
		DisplayName:      c.T("api.command_me.name"),
	}
}

func (me *MeProvider) DoCommand(c *Context, channelId string, message string) *model.CommandResponse {
	userChan := Srv.Store.User().Get(c.Session.UserId)
	var user *model.User
	if ur := <-userChan; ur.Err != nil {
		c.Err = ur.Err
		return nil
	} else {
		user = ur.Data.(*model.User)
	}

	var name = user.Username
	if len(user.Nickname) > 0 {
		name = user.Nickname
	} else if len(user.FirstName) > 0 {
		name = user.FirstName
	}

	return &model.CommandResponse{
		ResponseType: model.COMMAND_RESPONSE_TYPE_IN_CHANNEL,
		Text: "*" + name + " " + message + "*",
		Props: model.StringInterface{
			"class": "action",
		},
	}
}
