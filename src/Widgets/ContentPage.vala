//	This file is part of FeedReader.
//
//	FeedReader is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	FeedReader is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with FeedReader.  If not, see <http://www.gnu.org/licenses/>.

public class FeedReader.ContentPage : Gtk.Paned {

	private Gtk.Paned m_pane;
	private articleView m_article_view;
	private articleList m_articleList;
	private feedList m_feedList;
	public signal void showArticleButtons(bool show);


	public ContentPage()
	{
		logger.print(LogMessage.DEBUG, "ContentPage: setup FeedList");
		this.orientation = Gtk.Orientation.HORIZONTAL;

		this.set_position(settings_state.get_int("feeds-and-articles-width"));


		m_feedList = new feedList();

		m_pane = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
		m_pane.set_size_request(500, 500);
		m_pane.set_position(settings_state.get_int("feed-row-width"));
		m_pane.pack1(m_feedList, false, false);

		m_feedList.newFeedSelected.connect((feedID) => {
			m_articleList.setSelectedType(FeedListType.FEED);
			m_article_view.clearContent();
			m_articleList.setSelectedFeed(feedID);
			m_articleList.newHeadlineList();
		});

		m_feedList.newTagSelected.connect((tagID) => {
			m_articleList.setSelectedType(FeedListType.TAG);
			m_article_view.clearContent();
			m_articleList.setSelectedFeed(tagID);
			m_articleList.newHeadlineList();
		});

		m_feedList.newCategorieSelected.connect((categorieID) => {
			m_articleList.setSelectedType(FeedListType.CATEGORY);
			m_article_view.clearContent();
			m_articleList.setSelectedFeed(categorieID);
			m_articleList.newHeadlineList();
		});

		m_feedList.markAllArticlesAsRead.connect(markAllArticlesAsRead);
		m_feedList.updateArticleList.connect(updateArticleList);


		m_articleList = new articleList();
		setArticleListState((ArticleListState)settings_state.get_enum("show-articles"));

		m_pane.pack2(m_articleList, false, false);


		m_articleList.row_activated.connect((row) => {
			if(row.isUnread()){
				feedDaemon_interface.changeArticle(row.getID(), ArticleStatus.READ);
				row.updateUnread(ArticleStatus.READ);
				//row.removeUnreadIcon();
			}

			showArticleButtons(true);

			var window = ((rssReaderApp)GLib.Application.get_default()).getWindow();
			if(window != null)
			{
				var header = window.getHeaderBar();
				logger.print(LogMessage.DEBUG, "contentPage: set headerbar");
				header.setRead(row.isUnread());
				header.setMarked(row.isMarked());
			}

			if(m_article_view.getCurrentArticle() != row.getID())
				m_article_view.fillContent(row.getID());
		});

		m_articleList.noRowActive.connect(() => {
			showArticleButtons(false);
		});

		m_article_view = new articleView();


		this.pack1(m_pane, false, false);
		this.pack2(m_article_view, true, false);
	}

	public void ArticleListNEXT()
	{
		m_articleList.move(false);
	}

	public void ArticleListPREV()
	{
		m_articleList.move(true);
	}

	public void newHeadlineList(Gtk.StackTransitionType transition = Gtk.StackTransitionType.CROSSFADE)
	{
		m_articleList.newHeadlineList(transition);
	}

	public void newFeedList(bool defaultSettings = false)
	{
		m_feedList.newFeedlist(defaultSettings);
	}

	public void reloadArticleView()
	{
		m_article_view.reload();
	}

	public void updateFeedListCountUnread(string feedID, bool increase)
	{
		m_feedList.updateCounters(feedID, increase);
	}

	public void updateArticleList()
	{
		m_articleList.updateArticleList();
	}

	public void setArticleListState(ArticleListState state)
	{
		switch(state)
		{
			case ArticleListState.ALL:
				m_articleList.setOnlyUnread(false);
				m_articleList.setOnlyMarked(false);
				break;

			case ArticleListState.UNREAD:
				m_articleList.setOnlyUnread(true);
				m_articleList.setOnlyMarked(false);
				break;

			case ArticleListState.MARKED:
				m_articleList.setOnlyUnread(false);
				m_articleList.setOnlyMarked(true);
				break;
		}
	}

	public void setSearchTerm(string searchTerm)
	{
		m_articleList.setSearchTerm(searchTerm);
		m_article_view.setSearchTerm(searchTerm);
	}

	public void clearArticleView()
	{
		m_article_view.clearContent();
	}

	public string[] getExpandedCategories()
	{
		return m_feedList.getExpandedCategories();
	}

	public double getFeedListScrollPos()
	{
		return m_feedList.getScrollPos();
	}

	public string getSelectedFeedListRow()
	{
		return m_feedList.getSelectedRow();
	}

	public int getFeedListWidth()
	{
		return m_pane.get_position();
	}

	public void setFeedListWidth(int pos)
	{
		m_pane.set_position(pos);
	}

	public int getArticlePlusFeedListWidth()
	{
		return this.get_position();
	}

	public void setArticlePlusFeedListWidth(int pos)
	{
		this.set_position(pos);
	}

	public int getArticlesToLoad()
	{
		return m_articleList.getAmountOfRowsToLoad();
	}

	public double getArticleListScrollPos()
	{
		return m_articleList.getScrollPos();
	}

	public int getArticleViewScrollPos()
	{
		return m_article_view.getScrollPos();
	}

	public string getSelectedArticle()
	{
		return m_articleList.getSelectedArticle();
	}

	public ArticleStatus getSelectedArticleMarked()
	{
		return m_articleList.getSelectedArticleMarked();
	}

	public ArticleStatus getSelectedArticleRead()
	{
		return m_articleList.getSelectedArticleRead();
	}

	public string getSelectedURL()
	{
		return m_articleList.getSelectedURL();
	}

	public void markAllArticlesAsRead()
	{
		m_articleList.markAllAsRead();
	}

	public void toggleReadSelectedArticle()
	{
		m_articleList.toggleReadSelected();
	}

	public void toggleMarkedSelectedArticle()
	{
		m_articleList.toggleMarkedSelected();
	}

	public void openSelectedArticle()
	{
		m_articleList.openSelected();
	}

	public GLib.List<tag> getSelectedArticleTags()
	{
		string id = m_articleList.getSelectedID();
		var article = dataBase.read_article(id);
		unowned GLib.List<string> tagIDs = article.getTags();

		var tags = new GLib.List<tag>();

		foreach(string tagID in tagIDs)
		{
			tags.append(dataBase.read_tag(tagID));
		}

		return tags;
	}
}
